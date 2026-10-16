require "rails_helper"

# 競合テストの補助が、ロックの待ちを取り違えず、先行のトランザクションの失敗を隠さず、開いたままのトランザクションを
# 後始末で閉じる（docs/guides/testing.md「競合テスト」）。補助が誤ると、競合テストは何も確かめずに通る
RSpec.describe ConcurrencyHelpers do
  self.use_transactional_tests = false

  let!(:tenant) { FactoryBot.create(:tenant) }
  let(:lock_key) { SecureRandom.random_number(2**31) }

  after { delete_owned_rows([ tenant.id ], %w[sales_orders]) }

  def advisory_lock(key) = ApplicationRecord.lease_connection.execute("SELECT pg_advisory_xact_lock(#{key})")

  it "ロックの待ちは、後行の接続が先行の接続を待っているときだけ真になり、無関係な接続の待ちを数えない" do
    _, release, holder = hold_open(tenant.id) { advisory_lock(lock_key) }
    # 先行の接続を待つ、検査の対象ではない接続
    bystander = in_thread(tenant.id) { advisory_lock(lock_key) }
    expect(blocked_on_lock?(bystander, by: holder)).to be(true)

    # 先行の接続とは別のロックを取り、待たずに終わる接続
    _, other_release, other = hold_open(tenant.id) { advisory_lock(lock_key + 1) }
    free = in_thread(tenant.id) { sleep 0.3 }
    expect(blocked_on_lock?(free, by: other)).to be(false)

    commit(release, holder)
    commit(other_release, other)
    finish(bystander)
  end

  # 待つ先の表を取り違えると、受注の行ロックで直列になることを確かめる競合テストが、別の表の行ロックで待っても通る
  it "行ロックを待つ接続の待つ表の名前を返し、アドバイザリロックを待つ接続には空を返す" do
    order = Tenancy.with_tenant(tenant.id) { FactoryBot.create(:sales_order) }
    lock_order = -> { ApplicationRecord.lease_connection.exec_query("SELECT 1 FROM sales_orders WHERE id = $1 FOR UPDATE", "lock", [ order.id ]) }
    _, release, holder = hold_open(tenant.id) { lock_order.call; advisory_lock(lock_key) }

    row_waiter = in_thread(tenant.id) { lock_order.call }
    advisory_waiter = in_thread(tenant.id) { advisory_lock(lock_key) }
    expect(blocked_on_lock?(row_waiter, by: holder)).to be(true)
    expect(blocked_on_lock?(advisory_waiter, by: holder)).to be(true)

    expect(waiting_row_tables(row_waiter)).to eq([ "sales_orders" ])
    expect(waiting_row_tables(advisory_waiter)).to eq([])

    commit(release, holder)
    finish(row_waiter)
    finish(advisory_waiter)
  end

  it "同じスレッドを先行と後行に渡すと失敗する" do
    _, _release, holder = hold_open(tenant.id) { nil }

    expect { blocked_on_lock?(holder, by: holder) }.to raise_error(/同じ接続/)
  end

  it "ブロックの結果を返した後に先行のトランザクションが失敗すると、commit がその例外を送出する" do
    allow(Tenancy).to receive(:reset!).and_wrap_original do |original, connection|
      raise "コミットの後の失敗" if Thread.current[:fail_after_block]

      original.call(connection)
    end
    result, release, holder = hold_open(tenant.id) do
      Thread.current[:fail_after_block] = true
      :done
    end

    expect(result).to eq(:done)
    expect { commit(release, holder) }.to raise_error("コミットの後の失敗")
  end

  # 確定した請求書は、トリガーが所有ロールの削除も拒む（docs/architecture/data-model.md「請求（`billing`）」）
  it "後始末は確定した請求書と結んだ行も消し、止めたトリガーを戻す" do
    Tenancy.with_tenant(tenant.id) do
      invoice = FactoryBot.create(:invoice)
      FactoryBot.create(:invoice_tax_summary, invoice:)
      FactoryBot.create(:billable_item, invoice:)
      invoice.update!(issued_at: Time.current, invoice_number: "INV-#{SecureRandom.hex(4)}")
    end
    owner = OwnerConnection.lease_connection
    expect { owner.transaction { owner.execute("DELETE FROM billable_items WHERE owner_tenant_id = #{owner.quote(tenant.id)}") } }
      .to raise_error(ActiveRecord::StatementInvalid, /確定した請求書は変えられない/)

    delete_owned_rows([ tenant.id ], %w[invoice_tax_summaries billable_items invoices])

    left = %w[invoices invoice_tax_summaries billable_items].sum do |table|
      owner.select_value("SELECT count(*) FROM #{table} WHERE owner_tenant_id = $1", "Spec", [ tenant.id ])
    end
    expect(left).to eq(0)
    expect(owner.select_values(<<~SQL)).to all(eq("O"))
      SELECT tgenabled FROM pg_trigger
      WHERE NOT tgisinternal AND tgrelid IN ('invoices'::regclass, 'invoice_tax_summaries'::regclass, 'billable_items'::regclass)
    SQL
  end

  # 単価の行は、トリガーが所有ロールの削除も拒む（docs/adr/006 決定 3）
  it "後始末は単価の行も消し、止めたトリガーを戻す" do
    Tenancy.with_tenant(tenant.id) { FactoryBot.create(:item, unit_price: 100) }
    owner = OwnerConnection.lease_connection
    expect { owner.transaction { owner.execute("DELETE FROM item_prices WHERE owner_tenant_id = #{owner.quote(tenant.id)}") } }
      .to raise_error(ActiveRecord::StatementInvalid, /単価の行は消せない/)

    delete_owned_rows([ tenant.id ], %w[item_prices items])

    expect(owner.select_value("SELECT count(*) FROM item_prices WHERE owner_tenant_id = $1", "Spec", [ tenant.id ])).to eq(0)
    expect(owner.select_values("SELECT tgenabled FROM pg_trigger WHERE NOT tgisinternal AND tgrelid = 'item_prices'::regclass"))
      .to eq([ "O" ])
  end

  it "後始末は、そのテナントの名義で登録した送信のジョブも消し、別のテナントのジョブは残す" do
    other = FactoryBot.create(:tenant)
    [ tenant, other ].each do |owner|
      Tenancy.with_tenant(owner.id) { Notifications::Email.deliver_best_effort(:new_sales_order, params: { order_no: "SO-000001" }) }
    end
    jobs = -> { SolidQueue::Job.where(class_name: "Notifications::BestEffortMailJob").pluck(Arel.sql("arguments::json->>'tenant_id'")) }
    expect(jobs.call).to include(tenant.id, other.id)

    delete_owned_rows([ tenant.id ], [])

    expect(jobs.call).to include(other.id)
    expect(jobs.call).not_to include(tenant.id)
  ensure
    SolidQueue::Job.where(class_name: "Notifications::BestEffortMailJob").where("arguments LIKE ?", "%#{other.id}%").delete_all if other
  end

  # 監査の行は所有ロールでも消せないので、それが指すテナントとユーザーも残す（docs/guides/testing.md「競合テスト」）
  it "後始末はテナントを残し、テナント・ユーザー・監査の行の表を渡すと失敗する" do
    delete_owned_rows([ tenant.id ], [])
    expect(ApplicationRecord.lease_connection.select_value("SELECT count(*) FROM tenants WHERE id = $1", "Spec", [ tenant.id ])).to eq(1)

    %w[tenants users audit_logs].each do |table|
      expect { delete_owned_rows([ tenant.id ], [ table ]) }.to raise_error(ArgumentError, /#{table}/)
    end
  end

  it "後始末は、渡されなかった表にそのテナントの行が残れば失敗する" do
    Tenancy.with_tenant(tenant.id) { FactoryBot.create(:stock) }

    expect { delete_owned_rows([ tenant.id ], []) }.to raise_error(/stocks に行が残った/)
    delete_owned_rows([ tenant.id ], %w[stocks])
  end

  it "後始末は、コミットさせていないトランザクションを閉じ、スレッドを終わらせる" do
    _, _release, holder = hold_open(tenant.id) { nil }
    stopped = release_queue
    paused = in_thread(tenant.id) { stopped.pop }

    expect { finish_concurrent_threads }.not_to raise_error
    expect([ holder, paused ].map(&:alive?)).to eq([ false, false ])
  end
end
