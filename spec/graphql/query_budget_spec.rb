require "rails_helper"

# 画面の問い合わせごとに、一覧の親が 1 件のときと 20 件のときの SQL の件数が同じであることを確かめる
# （docs/architecture/graphql-schema.md「ページングと N+1」）。フィールドが親ごとに公開 API を呼ぶ N+1 は、
# 関連の読み込みではないので Bullet に見えない。
# 負例は、入れ子を引くソースが公開 API をキーごとに呼ぶと件数が違うことを確かめ、準備のデータが N+1 を件数に出せることを保証する
RSpec.describe "画面の問い合わせのクエリ数の予算" do
  SCREENS_DIR = Rails.root.join("spec/fixtures/graphql/screens")
  PAGE_SIZE = 20
  # Tenancy は Tenancy.with_tenant が流す set_config
  IGNORED_SQL = %w[SCHEMA TRANSACTION Tenancy].freeze

  # 操作名ごとに、操作者・応答の data から一覧の親までの道・入れ子ごとの各親の件数・入れ子を引くソースの公開 API とメソッドを持つ。
  # 単数の入れ子の件数は 1 で、値があることを表す。sources に無い入れ子は、親の値に含まれていてソースを通らない。
  # variables は first のほかに渡す変数を返すメソッドの名前。並べ替えと絞り込みを持つ一覧は、それを渡す。
  # 1 つの問い合わせが一覧を 2 つ持つなら、2 つ目からを
  # more_lists に { list:, nested: } で書き、seed は 1 回でどの一覧にも親を 1 件ずつ足す
  SCREENS = {
    "SupplierSalesOrders" => {
      actor: :supplier_member, list: %w[supplier salesOrders nodes], variables: :sales_orders_variables,
      nested: { "customer" => 1, "lines" => 2, "shipmentRequest" => 1 },
      sources: { "customer" => [ Partnerships::Directory, :tenants ], "lines" => [ Sales::SalesOrders, :lines_for ],
                 "shipmentRequest" => [ Fulfillment::ShipmentRequests, :for_sales_orders ] }
    },
    "SupplierShipmentRequests" => {
      actor: :supplier_member, list: %w[supplier shipmentRequests nodes], variables: :shipment_requests_variables,
      nested: { "salesOrder" => 1, "customer" => 1, "lines" => 2, "instruction" => 1 },
      sources: { "salesOrder" => [ Sales::SalesOrders, :by_ids ], "customer" => [ Partnerships::Directory, :tenants ],
                 "lines" => [ Fulfillment::ShipmentRequests, :lines_for ],
                 "instruction" => [ Fulfillment::ShipmentRequests, :instructions_for ] }
    },
    "SupplierItems" => {
      actor: :supplier_member, list: %w[supplier items nodes], variables: :items_variables,
      nested: { "stock" => 1 },
      sources: { "stock" => [ Inventory::Stocks, :for_items ] }
    },
    "SupplierStocks" => {
      actor: :supplier_member, list: %w[supplier stocks nodes], variables: :stocks_variables,
      nested: { "item" => 1 },
      sources: { "item" => [ Sales::Catalog, :items_for ] }
    },
    "SupplierStockMovements" => {
      actor: :supplier_member, list: %w[supplier stockMovements nodes], variables: :stock_movements_variables,
      nested: { "item" => 1 },
      sources: { "item" => [ Sales::Catalog, :items_for ] }
    },
    "SupplierPartMappings" => {
      actor: :supplier_member, list: %w[supplier partMappings nodes],
      nested: { "customer" => 1, "item" => 1 },
      sources: { "customer" => [ Partnerships::Directory, :tenants ], "item" => [ Sales::Catalog, :items_for ] }
    },
    "SupplierPartnerships" => {
      actor: :supplier_admin, list: %w[supplier partnerships],
      nested: { "buyer" => 1, "permissions" => 2 },
      sources: {}
    },
    "BuyerSuppliers" => {
      actor: :buyer_member, list: %w[buyer suppliers],
      nested: { "supplier" => 1, "permissions" => 2 },
      sources: {}
    },
    "SupplierDashboard" => {
      actor: :supplier_member, list: %w[supplier dashboard stocksBelowSafetyStock],
      nested: { "item" => 1 },
      more_lists: [ { list: %w[supplier dashboard shipmentRequestsDueSoon], nested: { "salesOrder" => 1, "customer" => 1 } } ],
      sources: { "item" => [ Sales::Catalog, :items_for ], "salesOrder" => [ Sales::SalesOrders, :by_ids ],
                 "customer" => [ Partnerships::Directory, :tenants ] }
    },
    "BuyerSupplierCatalog" => {
      actor: :buyer_member, list: %w[buyer supplier catalog nodes], variables: :catalog_variables,
      nested: {},
      sources: {}
    },
    "BuyerPurchaseOrders" => {
      actor: :buyer_member, list: %w[buyer purchaseOrders nodes], variables: :purchase_orders_variables,
      nested: { "supplier" => 1, "lines" => 2, "inboundShipments" => 1, "supplierShipments" => 1 },
      sources: { "supplier" => [ Partnerships::Directory, :tenants ], "lines" => [ Purchasing::PurchaseOrders, :lines_for ],
                 "inboundShipments" => [ Purchasing::PurchaseOrders, :inbound_shipments_for ],
                 "supplierShipments" => [ Fulfillment::PartnerShipments, :for_purchase_orders ] }
    }
  }.freeze

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:users) do
    {
      supplier_member: Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) },
      supplier_admin: Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) },
      buyer_member: Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) }
    }
  end

  def actor_for(key)
    user = users.fetch(key)
    tenant = user.owner_tenant_id == supplier.id ? supplier : buyer
    Partnerships::Actor.new(user_id: user.id, tenant_id: tenant.id, name: user.name, email: user.email, role: user.role,
      partner_code: tenant.partner_code)
  end

  def as_supplier(&) = Tenancy.with_tenant(supplier.id, &)

  # 一覧の親を count 件足す。関連先の ID で引く入れ子は、親ごとに別の関連先を作る。
  # 同じ関連先を指すと、ソースの中でキーが 1 つにまとまり、ソースを外しても同じ SQL が cached: true になって数えられない
  def seed(name, count)
    count.times { send(:"seed_#{name.underscore}") }
  end

  def seed_supplier_sales_orders
    as_supplier do
      order = FactoryBot.create(:sales_order)
      FactoryBot.create_list(:sales_order_line, 2, sales_order: order)
      FactoryBot.create(:shipment_request, sales_order_id: order.id, buyer_tenant_id: order.customer_tenant_id)
    end
  end

  def seed_supplier_shipment_requests
    as_supplier do
      order = FactoryBot.create(:sales_order)
      request = FactoryBot.create(:shipment_request, sales_order_id: order.id, buyer_tenant_id: order.customer_tenant_id)
      FactoryBot.create_list(:shipment_request_line, 2, shipment_request: request)
      FactoryBot.create(:shipping_instruction, shipment_request: request)
    end
  end

  def seed_supplier_items
    as_supplier { FactoryBot.create(:stock, item_id: FactoryBot.create(:item).id) }
  end

  # 安全在庫の絞り込みに当てるため、安全在庫を割った在庫にする
  def seed_supplier_stocks
    as_supplier { FactoryBot.create(:stock, item_id: FactoryBot.create(:item).id, on_hand: 0, safety_stock: 1) }
  end

  def seed_supplier_stock_movements
    as_supplier { FactoryBot.create(:stock_movement, item_id: seed_supplier_items.item_id) }
  end

  # 安全在庫を下回る在庫と、期限を過ぎた出荷依頼を 1 件ずつ足す。期限を過ぎていれば、今日を日本時間で決めても UTC で決めても入る
  def seed_supplier_dashboard
    as_supplier do
      FactoryBot.create(:stock, item_id: FactoryBot.create(:item).id, on_hand: 0, safety_stock: 1)
      order = FactoryBot.create(:sales_order)
      FactoryBot.create(:shipment_request, sales_order_id: order.id, buyer_tenant_id: order.customer_tenant_id, due_date: Date.current - 1)
    end
  end

  def seed_supplier_part_mappings
    as_supplier { FactoryBot.create(:customer_part_mapping) }
  end

  def seed_supplier_partnerships
    as_supplier { FactoryBot.create(:partnership, permissions: %w[view_catalog place_orders]) }
  end

  # 発注側の画面の取引先は、取引先ごとに受注側のテナントを作り、そのテナントで取引関係を結ぶ
  def partner_supplier(permissions)
    FactoryBot.create(:tenant).tap do |partner|
      Tenancy.with_tenant(partner.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions:) }
    end
  end

  def seed_buyer_suppliers
    partner_supplier(%w[view_catalog place_orders])
  end

  # カタログは取引先を 1 社選んで引くので、取引先は最初の 1 回だけ作り、親は品目にする
  def seed_buyer_supplier_catalog
    @catalog_supplier ||= partner_supplier(%w[view_catalog])
    Tenancy.with_tenant(@catalog_supplier.id) { FactoryBot.create(:item, :published) }
  end

  def catalog_variables = { "supplierTenantId" => @catalog_supplier.id }

  # 絞り込みの値は、seed が作る親がすべて当たるものにする。当たらないと 0 件どうしを比べ、N+1 を件数に出せない。
  # 受注と発注は、入れ子の取引先のソースの負例のために親ごとに別の取引先を作るので、取引先では絞らず受注日・発注日で絞る。
  # 状況は、seed が作る親の状況（照合前の明細の受注は品番照合待ち、入荷のある発注は入荷予定、出荷指示のある出荷依頼は出荷指示済）を含む集まりで絞る
  def order_date_filter = { "orderDateFrom" => (Date.current - 1).iso8601, "orderDateTo" => Date.current.iso8601 }

  def sales_orders_variables = { "orderBy" => { "field" => "DUE_DATE", "direction" => "DESC" }, "filter" => order_date_filter.merge("statuses" => %w[AWAITING_PART_MATCH RECEIVED]) }

  def purchase_orders_variables
    { "orderBy" => { "field" => "ORDER_NO", "direction" => "ASC" }, "filter" => order_date_filter.merge("statuses" => %w[INBOUND INSPECTED]) }
  end

  def shipment_requests_variables = { "orderBy" => { "field" => "DUE_DATE", "direction" => "ASC" }, "filter" => { "statuses" => %w[INSTRUCTED READY] } }

  def stocks_variables = { "orderBy" => { "field" => "AVAILABLE", "direction" => "ASC" }, "filter" => { "belowSafetyStock" => true } }

  def stock_movements_variables = { "filter" => { "types" => [ "INBOUND" ] } }

  # factory の品目コードは ITEM-<連番>
  def items_variables = { "orderBy" => { "field" => "CODE", "direction" => "DESC" }, "filter" => { "keyword" => "item-" } }

  # 経路 3 の出荷は発注ごとに 1 件（分納しない。data-model.md の shipments.shipment_request_id 一意）
  def seed_buyer_purchase_orders
    partner = partner_supplier(%w[view_shipments])
    order = Tenancy.with_tenant(buyer.id) do
      FactoryBot.create(:purchase_order, supplier_tenant_id: partner.id).tap do |purchase_order|
        FactoryBot.create_list(:purchase_order_line, 2, purchase_order:)
        FactoryBot.create(:inbound_shipment, purchase_order:)
      end
    end
    Tenancy.with_tenant(partner.id) do
      request = FactoryBot.create(:shipment_request, buyer_tenant_id: buyer.id, source_purchase_order_id: order.id)
      FactoryBot.create(:shipment, shipping_instruction: FactoryBot.create(:shipping_instruction, shipment_request: request))
    end
  end

  # FactoryOpsSchema.execute の間に流れた SQL を数える。データの準備の SQL は含めない
  def count_sql(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:cached] || IGNORED_SQL.include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
    count
  end

  # 画面の問い合わせを流し、応答を確かめてから SQL の件数を返す。
  # 認可の失敗や空の一覧で件数がそろう場合を通さないため、一覧の件数と入れ子の件数を先に確かめる
  def run_screen(name, screen, parents)
    actor = actor_for(screen[:actor])
    text = SCREENS_DIR.join("#{name.underscore}.graphql").read
    variables = GraphQL.parse(text).definitions.sole.variables.any? { _1.name == "first" } ? { "first" => PAGE_SIZE } : {}
    variables = variables.merge(send(screen[:variables])) if screen[:variables]
    result = nil
    count = Tenancy.with_tenant(actor.tenant_id) do
      Current.set(actor:) do
        count_sql { result = FactoryOpsSchema.execute(text, variables:, operation_name: name, context: { current_user: actor }) }
      end
    end

    expect(result["errors"]).to be_nil
    expect_lists(result.to_h, screen, parents)
    count
  end

  # 表のすべての一覧（more_lists を含む）について、親の件数と、各親の入れ子の件数を確かめる
  def expect_lists(result, screen, parents)
    [ screen.slice(:list, :nested), *screen[:more_lists] ].each do |list|
      nodes = result.dig("data", *list[:list])
      expect(nodes.size).to eq(parents)
      list[:nested].each do |field, size|
        expect(nodes.map { |node| node[field].is_a?(Array) ? node[field].size : [ node[field] ].compact.size }).to all(eq(size)), field
      end
    end
  end

  def counts_for(name, screen)
    seed(name, 1)
    one = run_screen(name, screen, 1)
    seed(name, PAGE_SIZE - 1)
    [ one, run_screen(name, screen, PAGE_SIZE) ]
  end

  it "画面の問い合わせの一覧のファイルは、1 ファイルに操作名の付いた問い合わせを 1 つ置き、どれも予算の表にある" do
    operations = SCREENS_DIR.glob("*.graphql").to_h do |path|
      definition = GraphQL.parse(path.read).definitions.sole
      expect(path.basename(".graphql").to_s).to eq(definition.name.underscore)
      [ definition.name, definition.operation_type ]
    end

    expect(operations.keys).to match_array(SCREENS.keys)
    expect(operations.values).to all(eq("query"))
  end

  # 選んだフィールドをたどり、リストの要素の下に置いたコネクションの道を返す。コネクションの nodes・edges もリストなので、
  # 一覧の要素の下のコネクションも当たる
  def self.connections_under_list(selections, owner, path = [], in_list: false)
    selections.flat_map do |selection|
      next connections_under_list(selection.selections, owner, path, in_list:) if selection.is_a?(GraphQL::Language::Nodes::InlineFragment)
      raise ArgumentError, "画面の問い合わせはフラグメントを使わない: #{selection.name}" unless selection.is_a?(GraphQL::Language::Nodes::Field)

      field = owner.get_field(selection.name)
      next [] if field.nil? || selection.selections.empty?

      type = field.type.unwrap
      here = [ *path, selection.name ]
      found = in_list && type.include?(GraphQL::Types::Relay::ConnectionBehaviors) ? [ here.join(".") ] : []
      found + connections_under_list(selection.selections, type, here, in_list: in_list || field.type.list?)
    end
  end

  def self.nested_connections(text, schema = FactoryOpsSchema)
    connections_under_list(GraphQL.parse(text).definitions.sole.selections, schema.query)
  end

  it "2 つ目からの一覧（more_lists）の件数と入れ子の件数も確かめる" do
    screen = SCREENS.fetch("SupplierDashboard")
    stocks = [ { "item" => { "id" => "i" } } ]
    request = { "salesOrder" => { "id" => "o" }, "customer" => { "id" => "c" } }
    response = ->(requests) { { "data" => { "supplier" => { "dashboard" => { "stocksBelowSafetyStock" => stocks,
      "shipmentRequestsDueSoon" => requests } } } } }

    expect_lists(response.call([ request ]), screen, 1)
    expect { expect_lists(response.call([]), screen, 1) }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    expect { expect_lists(response.call([ request.merge("customer" => nil) ]), screen, 1) }
      .to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it "画面の問い合わせは、一覧の中にコネクションを入れ子にしない" do
    offenders = SCREENS_DIR.glob("*.graphql").to_h { [ _1.basename.to_s, self.class.nested_connections(_1.read) ] }

    expect(offenders.reject { _2.empty? }).to eq({})
  end

  it "一覧の要素の下のコネクションを、取引先の一覧の下でも発注の一覧の下でも見つける" do
    expect(self.class.nested_connections("{ buyer { suppliers { catalog { nodes { code } } } } }")).to eq([ "buyer.suppliers.catalog" ])
    expect(self.class.nested_connections("{ buyer { purchaseOrders { nodes { id } } supplier(supplierTenantId: \"x\") { catalog { nodes { code } } } } }"))
      .to eq([])
    expect(self.class.nested_connections("{ supplier { salesOrders { nodes { lines { id } } } items { edges { node { id } } } } }"))
      .to eq([])
  end

  # いまのスキーマには、コネクションの要素の下にコネクションを持つ型が無いので、その形を持つスキーマを作って確かめる
  it "コネクションの nodes と edges.node の下のコネクションも、一覧の要素の下として見つける" do
    item = Class.new(GraphQL::Schema::Object) { graphql_name("NestedItem") && field(:code, String) }
    order = Class.new(GraphQL::Schema::Object) { graphql_name("NestedOrder") && field(:items, item.connection_type) }
    query = Class.new(GraphQL::Schema::Object) { graphql_name("NestedQuery") && field(:orders, order.connection_type) }
    schema = Class.new(GraphQL::Schema) { query(query) }

    expect(self.class.nested_connections("{ orders { nodes { items { nodes { code } } } } }", schema)).to eq([ "orders.nodes.items" ])
    expect(self.class.nested_connections("{ orders { edges { node { items { edges { node { code } } } } } } }", schema))
      .to eq([ "orders.edges.node.items" ])
    expect(self.class.nested_connections("{ orders { nodes { code: __typename } } }", schema)).to eq([])
  end

  # 画面の問い合わせの一覧の選択を totalCount だけにした問い合わせ。path は操作から一覧のコネクションまでの道
  def self.total_count_only(text, path)
    narrow = lambda do |node, rest|
      next node.merge(selections: [ GraphQL::Language::Nodes::Field.new(name: "totalCount") ]) if rest.empty?

      node.merge(selections: node.selections.map { _1.name == rest.first ? narrow.call(_1, rest.drop(1)) : _1 })
    end
    document = GraphQL.parse(text)
    document.merge(definitions: [ narrow.call(document.definitions.sole, path) ]).to_query_string
  end

  # 件数だけを選ぶ問い合わせ（画面のタブの件数）は、ページの行も値への写しも読まず、件数の 1 つの SQL だけを流す
  # （docs/architecture/graphql-schema.md「ページングと N+1」）。親を 2 件にし、件数が数えた値であることも確かめる。
  # 視点の直下の一覧に限る。取引先を選んでから引くカタログは、取引先を選ぶ SQL が加わる
  SCREENS.select { |_name, screen| screen[:list].size == 3 && screen[:list].last == "nodes" }.each do |name, screen|
    it "#{name} の一覧の totalCount だけを選ぶと、SQL は件数の 1 つだけ" do
      seed(name, 2)
      view, field = screen[:list]
      text = self.class.total_count_only(SCREENS_DIR.join("#{name.underscore}.graphql").read, [ view, field ])
      variables = { "first" => PAGE_SIZE, **(screen[:variables] ? send(screen[:variables]) : {}) }
      actor = actor_for(screen[:actor])
      result = nil
      count = Tenancy.with_tenant(actor.tenant_id) do
        Current.set(actor:) { count_sql { result = FactoryOpsSchema.execute(text, variables:, context: { current_user: actor }) } }
      end

      expect(result.to_h).to eq("data" => { view => { field => { "totalCount" => 2 } } })
      expect(count).to eq(1)
    end
  end

  SCREENS.each do |name, screen|
    describe name do
      it "一覧の親が 1 件と 20 件で、SQL の件数が同じ" do
        one, twenty = counts_for(name, screen)

        expect(twenty).to eq(one)
      end

      screen[:sources].each do |field, (api, method)|
        it "#{field} のソースが公開 API をキーごとに呼ぶと、1 件と 20 件で SQL の件数が違う（負例）" do
          allow(Sources::PublicApiSource).to receive(:new).and_wrap_original do |original, *args|
            original.call(*args).tap do |source|
              next unless args.first(2) == [ api, method ]

              fetch = source.method(:fetch)
              source.define_singleton_method(:fetch) { |ids| ids.flat_map { fetch.call([ _1 ]) } }
            end
          end

          one, twenty = counts_for(name, screen)

          expect(twenty).to be > one
        end
      end
    end
  end
end
