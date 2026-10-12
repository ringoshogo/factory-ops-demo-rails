require "rails_helper"

# 並んだ取り込み（docs/architecture/data-model.md「取り込み（`imports`）」）。テナントごとに 1 つという上限は 1 社がワーカーを
# 占めないためのもので、反映の正しさは行ロックが守る。同じテナントの 2 つの取り込みは在庫の行ロックで、同じ取り込みの 2 つの
# ジョブは imports の行ロックで直列になり、どの段階でも結果は 1 つのジョブのときと同じになる
RSpec.describe "並んだ取り込み" do
  self.use_transactional_tests = false

  let!(:tenant) { FactoryBot.create(:tenant).id }
  let!(:admin) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user, :admin) } }
  let(:actor) { Tenancy.with_tenant(tenant) { Partnerships::Authentication.acting_user(admin.id) } }
  let!(:item_ids) { Tenancy.with_tenant(tenant) { %w[A B].to_h { [ _1, FactoryBot.create(:item, code: _1).id ] } } }
  # 2 つのスレッドが出すイベントを集める
  let(:events) { Queue.new }
  let(:collector) { Struct.new(:events) { def emit(event) = events << event }.new(events) }

  around do |example|
    Rails.event.subscribe(collector)
    example.run
  ensure
    Rails.event.unsubscribe(collector)
  end

  after { delete_owned_rows([ tenant ], %w[stock_movements stocks import_rows imports import_files item_prices items]) }

  def tenancy(&) = Tenancy.with_tenant(tenant, &)

  def start(csv)
    tenancy do
      file = Imports::Files.store(actor, filename: "stocks.csv", content: csv).value
      Imports::Runs.start(actor, Imports::Runs.request(actor, file_id: file.id, kind: "stocks")).value
    end
  end

  # 置き場の行・件数・在庫・移動履歴。時刻と ID を除いて比べる
  def snapshot(import)
    tenancy do
      {
        rows: Imports::ImportRow.where(import_id: import.id).order(:row_number).pluck(:row_number, :data, :error, Arel.sql("applied_at IS NOT NULL")),
        import: Imports::Import.find(import.id).slice(:total_rows, :applied_rows, :failed_rows, :failure_reason).merge(status: Imports::Import.find(import.id).status),
        stocks: Inventory::Stocks.for_items(actor, item_ids.values).transform_values { [ _1.on_hand, _1.allocated ] },
        movements: Inventory::Stocks.movements(actor, first: 100, after: nil).values.map { [ _1.item_id, _1.type, _1.quantity ] }.sort
      }
    end
  end

  # 在庫の行は先に作っておく。行が無いと、後の接続は行の作成で一意索引を待ち、在庫の行ロックを外しても直列になる
  it "同じテナントの 2 つの在庫の取り込みを 2 つの接続で同時に反映しても、在庫の数量と移動履歴が行ごとに 1 回ずつになる" do
    tenancy { item_ids.each_value { Inventory::Adjustment.set_quantity(actor, item_id: _1, quantity: 1, reason: "棚卸") } }
    first, second = start("item_code,quantity\nA,5\nB,5\n"), start("item_code,quantity\nA,8\nB,8\n")
    [ first, second ].each { Imports::Staging.run(_1.id, tenant) { nil } }

    _, release, holder = hold_open(tenant) { Imports::Applying.next_chunk(first.id, tenant) }
    waiter = in_thread(tenant) { Imports::Applying.next_chunk(second.id, tenant) }

    expect(blocked_on_lock?(waiter, by: holder)).to be(true)
    commit(release, holder)
    finish(waiter)
    expect(snapshot(second)[:stocks]).to eq(item_ids.values.index_with { [ 8, 0 ] })
    expect(snapshot(second)[:movements]).to match_array(item_ids.values.flat_map { [ [ _1, "inbound", 1 ], [ _1, "inbound", 4 ], [ _1, "inbound", 3 ] ] })
    expect([ first, second ].map { snapshot(_1)[:import].values_at("applied_rows", "failed_rows") }).to eq([ [ 2, 0 ], [ 2, 0 ] ])
  end

  describe "同じ取り込みの 2 つのジョブ" do
    let(:csv) { "item_code,quantity\nA,3\nNONE,1\nB,4\n" }

    # 1 つのジョブで流した結果。別の取り込みで作り、比べる前に消す
    let(:expected) do
      import = start(csv)
      Imports::RunJob.new(import.id, tenant).perform_now
      result = snapshot(import)
      reset!
      result
    end

    def reset!
      OwnerConnection.lease_connection.transaction do
        %w[stock_movements stocks import_rows imports import_files].each do |table|
          OwnerConnection.lease_connection.execute("DELETE FROM #{table} WHERE owner_tenant_id = #{OwnerConnection.lease_connection.quote(tenant)}")
        end
      end
    end

    # 段階を 2 つの接続から同時に流す。先の接続はトランザクションを開いたまま止め、後の接続が imports の行ロックを待つことを確かめる
    def race(import, &stage)
      _, release, holder = hold_open(tenant) { stage.call(import) }
      waiter = in_thread(tenant) { stage.call(import) }

      expect(blocked_on_lock?(waiter, by: holder)).to be(true)
      commit(release, holder)
      finish(waiter)
    end

    # 件数のイベント（imports.chunk_applied・imports.finished）は、メトリクスの値の出どころなので、取り込みごとに行の数だけ出る
    def reported(import)
      emitted = Array.new(events.size) { events.pop }.select { _1[:name].start_with?("imports.") && _1[:payload][:import_id] == import.id }
      emitted.map { [ _1[:name], _1[:payload].values_at(:applied_rows, :failed_rows) ] }
    end

    it "置き場へ写す・反映する・締めるのそれぞれを 2 つの接続から同時に流しても、1 つのジョブのときと同じになる" do
      expected
      import = start(csv)

      race(import) { Imports::Staging.run(_1.id, tenant) { nil } }
      expect(snapshot(import)[:rows].size).to eq(3)
      race(import) { Imports::Applying.next_chunk(_1.id, tenant) }
      race(import) { Imports::Finalizing.run(_1.id, tenant) }

      expect(snapshot(import)).to eq(expected)
      expect(reported(import)).to eq([ [ "imports.chunk_applied", [ 2, 1 ] ], [ "imports.finished", [ 2, 1 ] ] ])
      expect(expected[:import]).to include("applied_rows" => 2, "failed_rows" => 1, status: :partially_failed)
    end
  end
end
