require "rails_helper"
require "prism"
require_relative "../support/cross_read"
require_relative "../support/env_helpers"

# シードと E2E の世界の作り方（README.md「開発環境」）。同じ DB に namespace ごとの世界を作れ、namespace ごとに冪等である。
# GraphQL を通らない入口なので、admin に限る操作は mutation と同じ規則を評価してから呼ぶ
# （docs/architecture/graphql-schema.md「役割による制限」）。流したジョブは Solid Queue のワーカーと同じ順で後始末し、
# 実行待ちの行と同時実行の制御のセマフォを残さない（solid_queue 1.7.0 の app/models/solid_queue/claimed_execution.rb の finalize）
RSpec.describe DemoWorld do
  include_context "RLS の SELECT と UPDATE を開く"
  include EnvHelpers

  def namespace = "w#{SecureRandom.hex(3)}"

  def actor_of(world, persona)
    account = world.accounts.find { _1.persona == persona }
    login = Partnerships::Authentication.authenticate(email: account.email, password: account.password)
    Tenancy.with_tenant(login.tenant_id) { Partnerships::Authentication.acting_user(login.user_id) }
  end

  def as(actor, &) = Tenancy.with_tenant(actor.tenant_id) { yield actor }

  # どのテナントの行も数える。RLS の SELECT を開くので、テナントの表の全行が見える
  def row_counts
    connection = ActiveRecord::Base.lease_connection
    tables = MatrixWorld.tenant_tables + %w[tenants solid_queue_jobs]
    Tenancy.with_tenant(SecureRandom.uuid) do
      cross_read!
      tables.to_h { [ _1, connection.select_value("SELECT count(*) FROM #{connection.quote_table_name(_1)}") ] }
    end
  end

  describe ".build" do
    it "同じ DB に namespace の違う 2 組を作れ、それぞれの 2 回目は行を増やさずに同じテナントとアカウントを返す" do
      first = described_class.build(namespace: "a#{SecureRandom.hex(3)}", variant: :seed)
      second_namespace = "b#{SecureRandom.hex(3)}"
      second = described_class.build(namespace: second_namespace, variant: :e2e)
      counts = row_counts

      expect(first.tenant_ids.values & second.tenant_ids.values).to be_empty
      expect(first.accounts.map(&:email) & second.accounts.map(&:email)).to be_empty
      expect(second.accounts.map(&:email)).to all(include("+#{second_namespace}@"))
      # 対照：2 組とも、受注と取り込みまで作っている
      expect(counts.values_at("sales_orders", "imports").map { _1 >= 2 }).to eq([ true, true ])

      again = [ described_class.build(namespace: first.accounts.first.email[/\+(.+)@/, 1], variant: :seed),
        described_class.build(namespace: second_namespace, variant: :e2e) ]
      expect(again).to eq([ first, second ])
      expect(row_counts).to eq(counts)
    end

    it "namespace が英小文字・数字・ハイフンでないか、variant が seed・e2e でなければ、何も作らずに例外にする" do
      counts = row_counts

      expect { described_class.build(namespace: "W 1", variant: :seed) }.to raise_error(ArgumentError, /namespace/)
      expect { described_class.build(namespace: nil, variant: :seed) }.to raise_error(ArgumentError, /namespace/)
      expect { described_class.build(namespace:, variant: :demo) }.to raise_error(ArgumentError, /variant/)
      expect(row_counts).to eq(counts)
    end

    it "公開 API が失敗を返したら、失敗のコードと項目と文を持つ例外で止まる" do
      allow(Purchasing::Ordering).to receive(:place).and_return(OperationResult.failure(:not_permitted, path: [ :supplier_tenant_id ]))
      expect { described_class.build(namespace:, variant: :seed) }.to raise_error(DemoWorld::Failed, "not_permitted supplier_tenant_id")

      allow(Purchasing::Ordering).to receive(:place).and_return(OperationResult.failure(:conflict, message: "closed"))
      expect { described_class.build(namespace:, variant: :seed) }.to raise_error(DemoWorld::Failed, "conflict closed")
    end

    it "取り込みがジョブを流し終えても終わっていなければ、例外で止まる" do
      allow(Imports::Runs).to receive(:find).and_wrap_original { |original, *args| original.call(*args).with(status: :queued) }

      expect { described_class.build(namespace:, variant: :seed) }.to raise_error(DemoWorld::Failed, /items.csv が終わらない（queued）/)
    end

    it "本番の環境では、DEMO_WORLD_ENABLED が無いか 1 でなければ、何も作らずに例外にする" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
      counts = row_counts

      [ nil, "true" ].each do |value|
        with_env("DEMO_WORLD_ENABLED" => value) do
          expect { described_class.build(namespace:, variant: :seed) }.to raise_error(DemoWorld::ProductionEnvironment)
        end
      end
      expect(row_counts).to eq(counts)
    end

    # 世界を作る途中で呼ぶ公開 API（テナントの作成・安全在庫）も、同じ条件で本番の環境を止めている。どれか 1 つでも条件を
    # 読まなければ、途中で止まる（docs/adr/009 決定 4）
    it "本番の環境でも、DEMO_WORLD_ENABLED=1 なら世界を最後まで作る" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))

      world = with_env("DEMO_WORLD_ENABLED" => "1") { described_class.build(namespace:, variant: :seed) }

      expect(world.tenant_ids.values).to all(be_present)
      expect(actor_of(world, "supplier_admin").role).to eq("admin")
    end
  end

  describe "variant: :e2e" do
    let!(:world) { described_class.build(namespace:, variant: :e2e) }
    let(:supplier) { actor_of(world, "supplier_admin") }

    # 止まっていられない状況は除く。発注の「送信済み」は受注側がイベントを受け取るまで、取り込みの「待機中・置き場へ写し中・反映中」は
    # ジョブが動くまでの状況で、どれも世界を作り終えるまでにジョブが進める
    def statuses_at_rest(type, transient: [])
      type.values.values.map(&:value).map(&:to_sym) - transient
    end

    it "受注・発注・出荷依頼・取り込みの状況の enum の、止まっていられる全値の行を持つ" do
      buyers = %w[granted_buyer_admin revoked_buyer_admin].map { actor_of(world, _1) }
      sales_orders = as(supplier) { Sales::SalesOrders.list(_1, first: 100, after: nil).values }
      purchase_orders = buyers.flat_map { |buyer| as(buyer) { Purchasing::PurchaseOrders.list(_1, first: 100, after: nil).values } }
      requests = as(supplier) { Fulfillment::ShipmentRequests.list(_1, first: 100, after: nil).values }
      imports = as(supplier) { Imports::Runs.list(_1, first: 100, after: nil).values }

      expect(sales_orders.map(&:status).uniq).to match_array(statuses_at_rest(Types::SalesOrderStatusType))
      expect(purchase_orders.map(&:status).uniq).to match_array(statuses_at_rest(Types::PurchaseOrderStatusType, transient: %i[sent]))
      expect(requests.map(&:status).uniq).to match_array(statuses_at_rest(Types::ShipmentRequestStatusType))
      expect(imports.map(&:status).uniq).to match_array(statuses_at_rest(Types::ImportStatusType, transient: %i[queued staging applying]))
      # 重ねて示す取消依頼中・取消審査中の行もある
      expect(purchase_orders.map(&:cancellation_pending)).to include(true, false)
      expect(sales_orders.map(&:cancellation_review_pending)).to include(true, false)
    end

    it "長い名前の品目と取引先を持ち、長い名前の品目を受注の明細に使う" do
      items = as(supplier) { Sales::Catalog.items(_1, first: 100, after: nil).values }
      longest = items.max_by { _1.name.length }
      order_ids = as(supplier) { Sales::SalesOrders.list(_1, first: 100, after: nil).values.map(&:id) }
      line_items = as(supplier) { Sales::SalesOrders.lines_for(_1, order_ids).values.flatten.map(&:item_name) }

      expect(longest.name).to eq(DemoWorld::LONG_ITEM[1])
      expect(line_items).to include(longest.name)
      expect(as(supplier) { Partnerships::Directory.for_supplier(_1).map { |partnership| partnership.buyer.name } })
        .to include(start_with(DemoWorld::LONG_BUYER_NAME))
    end

    # 合計の欄の「取消」（frontend/lib/format.ts の totalAmountText）を、E2E が一覧・詳細・かんばんで確かめる受注と発注
    it "品番照合待ちのまま取り消した、合計を持たない受注と発注を持つ" do
      buyer = actor_of(world, "granted_buyer_admin")
      sales_orders = as(supplier) { Sales::SalesOrders.list(_1, first: 100, after: nil).values }
      purchase_orders = as(buyer) { Purchasing::PurchaseOrders.list(_1, first: 100, after: nil).values }

      expect(sales_orders.select { _1.status == :cancelled }.map(&:total_amount)).to include(nil, be_positive)
      expect(purchase_orders.select { _1.status == :supplier_cancelled }.map(&:total_amount)).to include(nil, be_positive)
      # 対照：取り消していない受注にも、合計を持たない照合待ちの受注がある
      expect(sales_orders.select { _1.status == :awaiting_part_match }.map(&:total_amount)).to include(nil)
    end

    # 画面の一覧は 1 ページに 20 件を読む。E2E の一覧のページの確かめ（frontend/e2e/list-pagination.spec.ts）は、
    # 品目が 1 ページを超えて 2 ページ目まで続くことを当てにする
    it "品目は 22 件で、画面の 1 ページ（20 件）を超える" do
      expect(as(supplier) { Sales::Catalog.items(_1, first: 100, after: nil).values.size }).to eq(22)
    end
  end

  describe DemoWorld::Jobs do
    # ワーカーと同じく、実行待ちのジョブだけを流す。時刻を待つジョブと、同時実行の上限で待つジョブは動かさない
    it "実行待ちでないジョブは流さずに残し、実行待ちのジョブは流す" do
      tenant_id = FactoryBot.create(:tenant).id
      admin = Tenancy.with_tenant(tenant_id) { FactoryBot.create(:user, :admin) }
      actor = Tenancy.with_tenant(tenant_id) { Partnerships::Authentication.acting_user(admin.id) }
      import = Tenancy.with_tenant(tenant_id) do
        file = Imports::Files.store(actor, filename: "stocks.csv", content: "item_code,quantity\n").value
        Imports::Runs.start(actor, Imports::Runs.request(actor, file_id: file.id, kind: "stocks")).value
      end
      job = SolidQueue::Job.where(class_name: "Imports::RunJob", finished_at: nil).where("arguments LIKE ?", "%#{import.id}%").sole
      SolidQueue::ReadyExecution.where(job_id: job.id).delete_all
      SolidQueue::ScheduledExecution.create!(job:, scheduled_at: 1.hour.from_now, queue_name: job.queue_name, priority: job.priority)

      DemoWorld::Jobs.drain([ "Imports::RunJob" ])
      expect(job.reload.finished_at).to be_nil

      # 対照：同じジョブも、実行待ちになれば流す
      SolidQueue::ScheduledExecution.where(job_id: job.id).delete_all
      SolidQueue::ReadyExecution.create!(job:, queue_name: job.queue_name, priority: job.priority)
      DemoWorld::Jobs.drain([ "Imports::RunJob" ])
      expect(job.reload.finished_at).to be_present
    end

    it "テナントの設定の中では流さない。ジョブは宛先テナントの設定を開くので、入れ子になる" do
      expect { Tenancy.with_tenant(FactoryBot.create(:tenant).id) { DemoWorld::Jobs.drain } }.to raise_error(ArgumentError, /外で呼ぶ/)
    end
  end

  describe "流したジョブの後始末" do
    let!(:world) { described_class.build(namespace:, variant: :seed) }
    let(:supplier) { actor_of(world, "supplier_admin") }

    def semaphore = SolidQueue::Semaphore.find_by(key: "Imports::RunJob/#{world.tenant_ids.fetch(:supplier)}")

    it "イベントと取り込みのジョブの実行待ちの行を残さず、取り込みのセマフォを上限の値に戻す。次の取り込みのジョブは実行待ちになる" do
      ready = SolidQueue::ReadyExecution.joins(:job).where(job: { class_name: DemoWorld::Jobs::CLASS_NAMES })
      # 対照：流したジョブは終わった行として残る
      expect(SolidQueue::Job.where(class_name: DemoWorld::Jobs::CLASS_NAMES).where.not(finished_at: nil)).to exist
      expect(ready).not_to exist
      # セマフォの行は返した後も残る（solid_queue 1.7.0 の app/models/solid_queue/semaphore.rb の signal は値を足すだけで、行を消さない）
      expect(semaphore&.value).to eq(1)

      import = as(supplier) do |actor|
        file = Imports::Files.store(actor, filename: "stocks.csv", content: "item_code,quantity\nITM-019,1\n").value
        Imports::Runs.start(actor, Imports::Runs.request(actor, file_id: file.id, kind: "stocks")).value
      end
      job = SolidQueue::Job.where(class_name: "Imports::RunJob", finished_at: nil).where("arguments LIKE ?", "%#{import.id}%").sole
      expect([ job.ready?, job.blocked? ]).to eq([ true, false ])
      expect(semaphore.value).to eq(0)
    end
  end

  describe "admin に限る操作" do
    let!(:world) { described_class.build(namespace:, variant: :seed) }
    let(:supplier) { actor_of(world, "supplier_admin") }
    let(:buyer) { actor_of(world, "granted_buyer_admin") }
    let(:supplier_member) { actor_of(world, "supplier_member") }
    let(:buyer_member) { actor_of(world, "granted_buyer_member") }

    # 操作ごとの、member の操作者と引数と、規則が拒否したら呼ばれない公開 API。対象は世界の行から選ぶ
    def operations
      customer_id = world.tenant_ids.fetch(:granted_buyer)
      orders = as(supplier) { Sales::SalesOrders.list(_1, first: 100, after: nil).values }
      review = as(supplier) { Sales::CancellationReviews.for_sales_orders(_1, orders.map(&:id)).values.flatten.find { |r| r.decision.nil? } }
      item = as(supplier) { Sales::Catalog.items(_1, first: 1, after: nil).values.sole }
      price = as(supplier) { Sales::ItemPrices.history(_1, [ item.id ]).fetch(item.id).last }
      draft = as(supplier) { Billing::Invoices.list(_1, first: 100, after: nil).values.find { |invoice| invoice.state == :draft } }
      partnership = as(supplier) { Partnerships::Directory.for_supplier(_1).find { |p| p.buyer.id == customer_id } }
      purchase_orders = as(buyer) { Purchasing::PurchaseOrders.list(_1, first: 100, after: nil).values }
      inbound = as(buyer) do |actor|
        Purchasing::PurchaseOrders.inbound_shipments_for(actor, purchase_orders.select { _1.status == :inbound }.map(&:id)).values.flatten.sole
      end
      file = as(supplier_member) { Imports::Files.store(_1, filename: "items.csv", content: "x").value }

      {
        establish_partnership: [ supplier_member, { partner_code: "x" }, [ Partnerships::Management, :establish ] ],
        grant_permission: [ supplier_member, { partnership_id: partnership.id, permission: "view_catalog" }, [ Partnerships::Management, :grant ] ],
        revoke_partnership: [ supplier_member, { partnership_id: partnership.id }, [ Partnerships::Management, :revoke ] ],
        request_purchase_order_cancellation: [ buyer_member, { purchase_order_id: purchase_orders.find { _1.status == :accepted }.id, reason: "x" },
          [ Purchasing::Ordering, :request_cancellation ] ],
        inspect_inbound_shipment: [ buyer_member, { inbound_shipment_id: inbound.id, lines: [] }, [ Purchasing::ReceiptInspections, :record ] ],
        approve_cancellation_review: [ supplier_member, { cancellation_review_id: review.id }, [ Sales::CancellationReviews, :approve ] ],
        reject_cancellation_review: [ supplier_member, { cancellation_review_id: review.id }, [ Sales::CancellationReviews, :reject ] ],
        cancel_sales_order: [ supplier_member, { sales_order_id: orders.find { _1.status == :received }.id }, [ Sales::OrderCancellation, :cancel ] ],
        set_billing_term: [ supplier_member, { customer_tenant_id: customer_id, closing_day: 20 }, [ Billing::Terms, :set ] ],
        close_billing_period: [ supplier_member, { customer_tenant_id: customer_id, closing_date: Date.current }, [ Billing::Closing, :close ] ],
        issue_invoice: [ supplier_member, { invoice_id: draft.id }, [ Billing::Closing, :issue ] ],
        schedule_item_price: [ supplier_member, { item_id: item.id, unit_price: 1, effective_on: Date.current + 1 }, [ Sales::ItemPrices, :schedule ] ],
        correct_item_price: [ supplier_member, { item_price_id: price.id, unit_price: 1, reason: "x" }, [ Sales::ItemPrices, :correct ] ],
        start_import: [ supplier_member, { file_id: file.id, kind: "items" }, [ Imports::Runs, :start ] ]
      }
    end

    it "操作者が member なら、どの操作も公開 API を呼ばずに例外で止まる" do
      table = operations
      table.each_value { |(_, _, (api, method))| allow(api).to receive(method).and_call_original }

      # 対照：表は Operations の公開のメソッドをすべて持つ
      expect(table.keys).to match_array(DemoWorld::Operations.singleton_methods)
      table.each do |name, (actor, arguments, _)|
        expect { as(actor) { DemoWorld::Operations.public_send(name, actor, **arguments) } }
          .to raise_error(DemoWorld::Operations::Forbidden), name.to_s
      end
      table.each_value { |(_, _, (api, method))| expect(api).not_to have_received(method) }
    end

    # 規則の正本は mutation の宣言で、対象に評価するか操作者に評価するかは mutation の find_target の有無で決まる
    # （docs/architecture/graphql-schema.md「基底クラス」）
    it "操作と mutation の表は Operations の公開のメソッドと同じで、どの操作も mutation と同じく対象を渡すか渡さないかを決める" do
      expect(DemoWorld::Operations::MUTATIONS.keys).to match_array(DemoWorld::Operations.singleton_methods)

      passed = {}
      allow(DemoWorld::Operations).to receive(:authorize!).and_wrap_original do |original, operation, actor, target = nil|
        passed[operation] = !target.nil?
        original.call(operation, actor, target)
      end
      operations.each do |name, (actor, arguments, _)|
        expect { as(actor) { DemoWorld::Operations.public_send(name, actor, **arguments) } }
          .to raise_error(DemoWorld::Operations::Forbidden), name.to_s
      end

      targeted = DemoWorld::Operations::MUTATIONS.transform_values do |mutation|
        mutation.method_defined?(:find_target) || mutation.private_method_defined?(:find_target)
      end
      # 対照：対象を引く mutation と引かない mutation の両方がある
      expect(targeted.values.uniq).to contain_exactly(true, false)
      expect(passed).to eq(targeted)
      # 対象の有無が mutation と食い違えば、admin でも規則を評価せずに止まる
      authorize = ->(*arguments) { as(supplier) { DemoWorld::Operations.send(:authorize!, *arguments) } }
      expect { authorize.(:grant_permission, supplier) }.to raise_error(DemoWorld::Operations::Mismatch)
      expect { authorize.(:establish_partnership, supplier, supplier) }.to raise_error(DemoWorld::Operations::Mismatch)
      # 対照：食い違わなければ、admin は規則を通る
      expect(authorize.(:establish_partnership, supplier)).to be_nil
    end

    it "操作者が admin なら、規則を通って公開 API を呼ぶ" do
      result = as(supplier) { DemoWorld::Operations.set_billing_term(_1, customer_tenant_id: world.tenant_ids.fetch(:granted_buyer), closing_day: 20) }

      expect(result.value).to have_attributes(closing_day: 20)
    end

    # admin に限る公開 API は Operations からだけ呼び、規則の評価を飛ばす呼び出しを DemoWorld の中に置かない。
    # 呼び出しは Prism の構文木から拾い、コメントと文字列の中の語を呼び出しと取り違えない。
    # 対象は docs/architecture/graphql-schema.md「役割による制限」の表の admin に限る操作のすべてで、
    # Operations がまだ持たない操作（権限付与の取り下げ・下書きの破棄）も含める
    it "DemoWorld は、admin に限る公開 API を Operations の外から呼ばない" do
      through_operations = operations.values.map { |(_, _, (api, method))| [ api.name, method ] }
      admin_apis = through_operations + [ [ "Partnerships::Management", :withdraw ], [ "Billing::Closing", :discard ] ]
      calls = lambda do |path|
        found = []
        visit = lambda do |node|
          if node.is_a?(Prism::CallNode) && node.receiver.is_a?(Prism::ConstantPathNode)
            found << [ node.receiver.full_name, node.name ]
          end
          node.compact_child_nodes.each { visit.call(_1) }
        end
        visit.call(Prism.parse_file(path).value)
        found & admin_apis
      end

      expect(calls.call(Rails.root.join("lib/demo_world/operations.rb").to_s)).to match_array(through_operations)
      expect((Dir[Rails.root.join("lib/demo_world.rb")] + Dir[Rails.root.join("lib/demo_world/*.rb")])
        .reject { _1.end_with?("operations.rb") }.flat_map { calls.call(_1) }).to eq([])
    end
  end
end
