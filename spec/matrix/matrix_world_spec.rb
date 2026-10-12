require "rails_helper"
require_relative "../support/matrix_world"

# 行列の世界をファイルごとに作る補助が、example で足した行とテナントの設定を次の example に渡さず、
# ファイルの終わりに世界を残さず、世界のトランザクションが途中で閉じたことを失敗にする
# （docs/guides/testing.md「行列テストとの分担」）。補助が誤ると、行列テストは前の example が汚した世界の上で通る
RSpec.describe MatrixWorld do
  # 世界を包むトランザクションを、この spec の example ごとのトランザクションの外で開く
  self.use_transactional_tests = false

  let(:connection) { ActiveRecord::Base.lease_connection }
  let(:pool) { ActiveRecord::Base.connection_pool }

  # example が失敗して世界を閉じ損ねても、接続の固定を残して後の spec を巻き込まない
  after do
    pool.unpin_connection! while pool.instance_variable_get(:@pinned_connection)
  end

  def count_tenants(ids)
    connection.select_value("SELECT count(*) FROM tenants WHERE id IN (#{ids.map { connection.quote(_1) }.join(', ')})")
  end

  def tenant_setting = connection.select_value("SELECT current_setting('app.tenant_id', true)")

  def cross_read_policies
    connection.select_value("SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND policyname = 'matrix_cross_read'")
  end

  # 行列の spec と同じ形の内側の example group を走らせ、example の結果を返す。
  # 実行の絞り込み（-e など）と --order rand を内側に掛けず、書いた順に走らせる
  def run_inner_group(cross_read: false, **metadata, &body)
    group = RSpec.describe("内側の行列", order: :defined, **metadata) do
      MatrixWorld.share_per_file(self, cross_read:)
      instance_exec(&body)
    end
    RSpec.world.example_groups.delete(group)
    RSpec.world.filtered_examples[group] = group.examples
    group.run(RSpec::Core::NullReporter)
    group.examples.map { [ _1.execution_result.status, _1.execution_result.exception&.message ] }
  end

  it "example で足した行とテナントの設定は次の example に残らず、ファイルの終わりに世界が残らない" do
    seen = {}
    results = run_inner_group do
      it "行を足し、セッションのテナントを設定する" do
        seen[:tenants] = world.tenants.values
        seen[:item] = world.as(:supplier) { FactoryBot.create(:item).id }
        connection = ActiveRecord::Base.lease_connection
        connection.select_value("SELECT set_config('app.tenant_id', $1, false)", "Spec", [ world.tenants[:supplier] ])
        expect(world.as(:supplier) { connection.select_value("SELECT count(*) FROM items WHERE id = $1", "Spec", [ seen[:item] ]) }).to eq(1)
      end

      it "前の example の行と設定は無く、世界の行はある" do
        connection = ActiveRecord::Base.lease_connection
        expect(connection.select_value("SELECT current_setting('app.tenant_id', true)")).to be_blank
        world.as(:supplier) do
          expect(connection.select_value("SELECT count(*) FROM items WHERE id = $1", "Spec", [ seen[:item] ])).to eq(0)
          expect(connection.select_value("SELECT count(*) FROM items WHERE id = $1", "Spec", [ world.row("items", :supplier).id ])).to eq(1)
        end
      end
    end

    expect(results).to eq([ [ :passed, nil ], [ :passed, nil ] ])
    expect(seen[:tenants].size).to eq(MatrixWorld::PERSONAS.size)
    expect(count_tenants(seen[:tenants])).to eq(0)
    expect(connection.transaction_open?).to be(false)
  end

  it "世界のオブジェクトの属性を書き換えると例外になる" do
    world = MatrixWorld.open
    user = world.users[:supplier]

    expect(user.email).to be_present
    expect { user.name = "書き換え" }.to raise_error(FrozenError)
    expect { world.tenants[:stranger] = "書き換え" }.to raise_error(FrozenError)
  ensure
    MatrixWorld.close if world
  end

  it "世界のトランザクションがファイルの終わりより前に閉じると、閉じるときに失敗し、接続の固定は外れる" do
    world = MatrixWorld.open
    tenants = world.tenants.values
    expect(count_tenants(tenants)).to eq(tenants.size)

    connection.rollback_transaction

    expect { MatrixWorld.close }.to raise_error(/ファイルの終わりより前に閉じた/)
    expect(connection.transaction_open?).to be(false)
    expect(count_tenants(tenants)).to eq(0)
  end

  it "接続を固定した後の確かめで失敗しても、固定を残さずに送出し、次の世界を開いて閉じられる" do
    allow(connection).to receive(:verify!).and_raise(ActiveRecord::ConnectionNotEstablished, "確かめの失敗")

    expect { MatrixWorld.open }.to raise_error(ActiveRecord::ConnectionNotEstablished, "確かめの失敗")
    expect(pool.instance_variable_get(:@pinned_connection)).to be_nil

    allow(connection).to receive(:verify!).and_call_original
    world = MatrixWorld.open
    expect(count_tenants(world.tenants.values)).to eq(MatrixWorld::PERSONAS.size)
  ensure
    MatrixWorld.close if world
  end

  it "接続を借りる前に失敗したら、その例外をそのまま送出する" do
    allow(pool).to receive(:pin_connection!).and_raise(ActiveRecord::ConnectionTimeoutError, "借りられない")

    expect { MatrixWorld.open }.to raise_error(ActiveRecord::ConnectionTimeoutError, "借りられない")
    expect(pool.instance_variable_get(:@pinned_connection)).to be_nil
  end

  it "世界を作った後にテナントの設定が残っていれば、作った行と接続の固定を残さずに失敗する" do
    created = []
    allow(MatrixWorld).to receive(:new).and_wrap_original do |original|
      original.call.tap do |world|
        created.concat(world.tenants.values)
        connection.select_value("SELECT set_config('app.tenant_id', $1, false)", "Spec", [ world.tenants[:supplier] ])
      end
    end

    expect { MatrixWorld.open }.to raise_error(/テナントの設定が残っている/)
    expect(created.size).to eq(MatrixWorld::PERSONAS.size)
    expect(count_tenants(created)).to eq(0)
    expect(connection.transaction_open?).to be(false)
    expect(tenant_setting).to be_blank
  end

  describe "RLS の SELECT を開く補助（cross_read: true）" do
    # ダッシュボードの 4 つの集計。どれも自社の行を数える公開 API で、scope を外すと他社の行も数える
    def dashboard(world)
      actor = Partnerships::Actor.new(user_id: nil, tenant_id: world.tenants[:supplier], name: "", email: "", role: "admin",
        partner_code: "")
      world.as(:supplier) do
        { sales_order_counts: Sales::SalesOrders.count_by_status(actor),
          stocks_below_safety_stock: Inventory::Stocks.below_safety_stock(actor).size,
          shipment_requests_due_soon: Fulfillment::ShipmentRequests.due_within(actor, today: Date.current, days: 7).size,
          unbilled_total: Billing::BillableItems.unbilled_total(actor) }
      end
    end

    # 4 つの公開 API が通す policy の relation_scope を、絞らずに relation を返すものに差し替える。
    # scope の入口（各パッケージの Scope）はパッケージの外に見せないので、公開している policy の側で外す
    def remove_dashboard_scopes
      [ Sales::SalesOrderPolicy, Inventory::StockPolicy, Fulfillment::ShipmentRequestPolicy, Billing::InvoicePolicy ].each do |policy|
        allow(policy).to receive(:new).and_wrap_original do |original, *args, **options|
          original.call(*args, **options).tap { |instance| allow(instance).to receive(:apply_scope) { |relation, **| relation } }
        end
      end
    end

    # 2 回目の入口の行列が空振りしないことのガード。設定を on にした応答が他社の行を含まなければ、
    # scope を外しても 2 回目は 1 回目と同じ応答になり、何も捕まえない
    it "世界の間だけポリシーがあり、設定を on にした生 SQL・公開 API・入口の要求は、scope を外すと他社の行を読む" do
      seen = {}
      spec = self
      results = run_inner_group(cross_read: true, type: :request) do
        it "設定を on にした生 SQL は、どの表でも全ペルソナの行を読む" do
          connection = ActiveRecord::Base.lease_connection
          seen[:policies] = connection.select_value("SELECT count(*) FROM pg_policies WHERE policyname = 'matrix_cross_read'")
          owners = lambda do
            world.as(:supplier) do
              MatrixWorld.tenant_tables.index_with do |table|
                connection.select_values("SELECT DISTINCT owner_tenant_id FROM #{connection.quote_table_name(table)}")
                  .filter_map { world.persona_of(_1) if world.tenants.value?(_1) }.sort
              end
            end
          end
          closed = owners.call
          expect(closed["sales_orders"]).to eq([ :supplier ])

          MatrixCrossRead.on!
          expect(owners.call).to eq(MatrixWorld.tenant_tables.index_with { MatrixWorld::PERSONAS.sort })
        end

        it "設定を on にしてダッシュボードの 4 つの公開 API から scope を外すと、各集計が他社の行で変わる" do
          scoped = spec.dashboard(world)
          spec.remove_dashboard_scopes
          expect(spec.dashboard(world)).to eq(scoped)

          MatrixCrossRead.on!
          unscoped = spec.dashboard(world)
          expect(unscoped.keys.select { unscoped[_1] == scoped[_1] }).to be_empty
          expect(unscoped[:sales_order_counts].values.sum).to be > scoped[:sales_order_counts].values.sum
          expect(unscoped[:stocks_below_safety_stock]).to be > scoped[:stocks_below_safety_stock]
          expect(unscoped[:shipment_requests_due_soon]).to be > scoped[:shipment_requests_due_soon]
          expect(unscoped[:unbilled_total]).to be > scoped[:unbilled_total]
        end

        # 入口の行列の 2 回目と同じ経路（要求が世界の接続で読む）で設定が効くこと
        it "設定を on にして scope を外すと、入口の行列のダッシュボードの要求の応答が変わる" do
          dashboard = { query: "{ supplier { dashboard { unbilledTotal } } }" }
          login_as(world.users[:supplier])
          post "/graphql", params: dashboard, as: :json
          scoped = response.parsed_body
          spec.remove_dashboard_scopes
          post "/graphql", params: dashboard, as: :json
          expect(response.parsed_body).to eq(scoped)

          MatrixCrossRead.on!
          post "/graphql", params: dashboard, as: :json
          # BigInt は文字列で返るので、数に直して比べる
          expect(response.parsed_body.dig("data", "supplier", "dashboard", "unbilledTotal").to_i)
            .to be > scoped.dig("data", "supplier", "dashboard", "unbilledTotal").to_i
        end
      end

      expect(results).to eq([ [ :passed, nil ], [ :passed, nil ], [ :passed, nil ] ])
      expect(seen[:policies]).to eq(MatrixWorld.tenant_tables.size)
      expect(cross_read_policies).to eq(0)
    end

    it "足す途中で失敗すると、足した分を残さずに送出する" do
      owner = OwnerConnection.connection_pool.lease_connection
      created = 0
      allow(owner).to receive(:execute).and_wrap_original do |original, sql, *rest|
        if sql.include?("CREATE POLICY")
          raise ActiveRecord::StatementInvalid, "3 つ目の表で失敗" if created == 2

          created += 1
        end
        original.call(sql, *rest)
      end

      expect { MatrixCrossRead.add! }.to raise_error(ActiveRecord::StatementInvalid, "3 つ目の表で失敗")
      expect(created).to eq(2)
      expect(cross_read_policies).to eq(0)
    ensure
      OwnerConnection.connection_pool.release_connection
    end

    it "世界を開く途中で失敗すると、足したポリシーを外して送出する" do
      allow(MatrixWorld).to receive(:open).and_raise(ActiveRecord::ConnectionTimeoutError, "世界を開けない")

      results = run_inner_group(cross_read: true) { it("走らない") { nil } }

      expect(results.first.last).to include("世界を開けない")
      expect(cross_read_policies).to eq(0)
    end

    # 同じテストの DB で行列を流すほかの実行のポリシーを、足すのに失敗した側が消すと、ほかの実行の 2 回目が空振りする
    it "同じ名前のポリシーがすでにあれば、足さずに失敗し、あったポリシーを外さない" do
      MatrixCrossRead.add!

      results = run_inner_group(cross_read: true) { it("走らない") { nil } }

      expect(results.first.last).to include("matrix_cross_read のポリシーがすでにある")
      expect(cross_read_policies).to eq(MatrixWorld.tenant_tables.size)
    ensure
      MatrixCrossRead.remove!
    end

    it "接続先の名前がテストの DB でなければ、ポリシーを足さずに失敗する" do
      owner = OwnerConnection.connection_pool.lease_connection
      allow(owner).to receive(:current_database).and_return("factory_ops_demo_rails_development")

      expect { MatrixCrossRead.add! }.to raise_error(/テストの DB ではない factory_ops_demo_rails_development/)
      expect(cross_read_policies).to eq(0)
    ensure
      OwnerConnection.connection_pool.release_connection
    end
  end
end
