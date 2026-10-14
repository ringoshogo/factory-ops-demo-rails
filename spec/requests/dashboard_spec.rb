require "rails_helper"

# 受注側のダッシュボードの入口。画面の問い合わせの応答が、4 つの公開 API の集計と同じ値を返す
# （docs/architecture/graphql-schema.md「読み取りの一覧」）。集計の境界は、各公開 API の spec が確かめる
RSpec.describe "受注側のダッシュボード", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:actor) { Partnerships::Actor.new(user_id: member.id, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:screen) { Rails.root.join("frontend/graphql/supplier/SupplierDashboard.graphql").read }
  # 日本時間では 10 月 12 日の 1 時で、UTC ではまだ 10 月 11 日
  let(:now) { Time.utc(2026, 10, 11, 16, 0) }
  let(:today) { Date.new(2026, 10, 12) }

  def as_supplier(&) = Tenancy.with_tenant(supplier.id, &)

  def dashboard = travel_to(now) { query(screen).dig("supplier", "dashboard") }

  def stock_below(code)
    as_supplier { FactoryBot.create(:stock, item_id: FactoryBot.create(:item, code:).id, on_hand: 1, safety_stock: 5) }
  end

  before do
    as_supplier do
      FactoryBot.create(:sales_order, cancelled_at: Time.current)
      FactoryBot.create(:sales_order_line, quantity: 1)
      %w[NUT-1 BOLT-1].each { stock_below(_1) }
      order = FactoryBot.create(:sales_order)
      FactoryBot.create(:shipment_request, sales_order_id: order.id, buyer_tenant_id: order.customer_tenant_id, due_date: today + 7)
      FactoryBot.create(:billable_item, unit_price: 120, quantity: 3)
    end
    login_as(member)
  end

  it "画面の問い合わせが、4 つの公開 API と同じ値を返す。member も読め、今日は日本時間で決まる" do
    expected = as_supplier do
      { counts: Sales::SalesOrders.count_by_status(actor),
        stocks: Inventory::Stocks.below_safety_stock(actor).map(&:item_id),
        requests: Fulfillment::ShipmentRequests.due_within(actor, today:, days: 7).map(&:id),
        unbilled: Billing::BillableItems.unbilled_total(actor) }
    end

    result = dashboard

    expect(result.fetch("businessDate")).to eq("2026-10-12")
    expect(result.fetch("salesOrderCounts").to_h { [ _1.fetch("status").downcase.to_sym, _1.fetch("count") ] }).to eq(expected[:counts])
    expect(result.fetch("stocksBelowSafetyStock").map { _1.dig("item", "id") }).to match_array(expected[:stocks])
    expect(result.fetch("shipmentRequestsDueSoon").map { _1.fetch("id") }).to eq(expected[:requests])
    expect(result.fetch("unbilledTotal")).to eq(expected[:unbilled].to_s)
    # 対照：比べた値はどれも空でない
    expect([ expected[:counts][:cancelled], expected[:counts][:awaiting_part_match], expected[:stocks].size, expected[:requests].size,
             expected[:unbilled] ]).to eq([ 1, 1, 2, 1, 360 ])
  end

  # リゾルバは受注の一覧の規則だけを評価するので、ほかの 3 つの一覧の規則が役割で違う答えを返すと、
  # その一覧を読めない役割にもダッシュボードが集計を返す（docs/architecture/graphql-schema.md「読み取りの一覧」）
  # 業務の今日はアプリの時刻帯（日本時間）の Date.current で決まり、受注日とダッシュボードの今日が同じ出どころになる
  # （docs/architecture/context-map.md「検収と請求の流れ」、docs/architecture/graphql-schema.md「読み取りの一覧」）
  it "日本時間の 0〜9 時に作った受注の受注日と、ダッシュボードの今日が、どちらも日本時間の日付になる" do
    buyer = FactoryBot.create(:tenant)
    event = Contracts::PurchaseOrderPlaced.new(purchase_order_id: SecureRandom.uuid, buyer_tenant_id: buyer.id,
      supplier_tenant_id: supplier.id, desired_delivery_on: nil,
      lines: [ { "purchase_order_line_id" => SecureRandom.uuid, "part_number" => "P-1", "quantity" => 1 } ])
    travel_to(now) { as_supplier { Sales::PurchaseOrderTranslator.handle(event) } }
    order_id = as_supplier { Sales::SalesOrders.list(actor, first: 10, after: nil).values.find { _1.customer_tenant_id == buyer.id }.id }

    result = travel_to(now) do
      query("query($id: ID!) { supplier { dashboard { businessDate } salesOrder(id: $id) { orderDate } } }", id: order_id)
    end

    # 対照：この時刻の UTC の日付は前日である
    expect(now.utc.to_date).to eq(Date.new(2026, 10, 11))
    expect([ result.dig("supplier", "dashboard", "businessDate"), result.dig("supplier", "salesOrder", "orderDate") ])
      .to eq([ "2026-10-12", "2026-10-12" ])
  end

  it "4 つの一覧の規則が、admin と member のどちらにも、ダッシュボードの規則と同じ答えを返す" do
    answers = %w[admin member].to_h do |role|
      user = actor.with(role:)
      [ role, [ Sales::SalesOrderPolicy, Inventory::StockPolicy, Fulfillment::ShipmentRequestPolicy, Billing::InvoicePolicy ]
        .map { _1.new(user:).apply(:list?) } ]
    end

    expect(answers).to eq("admin" => [ true ] * 4, "member" => [ true ] * 4)
    expect(Resolvers::Supplier::DashboardResolver.authorization_policy).to eq(Sales::SalesOrderPolicy)
    expect(Resolvers::Supplier::DashboardResolver.authorization_rule).to eq(:list?)
  end

  it "受注の件数の状況が、GraphQL の受注の状況の値とそろう" do
    expect(as_supplier { Sales::SalesOrders.count_by_status(actor).keys })
      .to match_array(Types::SalesOrderStatusType.values.values.map(&:value))
  end

  # 受注番号も主キーも作った順に増えるので、作った受注では主キーの順でも同じ並びになり、確かめにならない。
  # 主キーの順と受注番号の順を逆にした 2 つの受注で確かめる。明細の無い受注の状況は引当済になる
  it "かんばんの画面の問い合わせが、未完了の列の希望納期の同じ受注を受注番号の昇順に並べる" do
    kanban = Rails.root.join("frontend/graphql/supplier/SupplierKanban.graphql").read
    as_supplier do
      { "00000000-0000-7000-8000-000000000002" => "SO-K00001", "00000000-0000-7000-8000-000000000001" => "SO-K00002" }.each do |id, order_no|
        FactoryBot.create(:sales_order, id:, order_no:, due_date: today)
      end
    end

    expect(query(kanban).dig("supplier", "allocated", "nodes").map { _1["orderNo"] }.first(2)).to eq(%w[SO-K00001 SO-K00002])
  end

  # 上の example は引当済の列の並びだけを見るので、ほかの列の並べ替えの引数は文書で確かめる
  it "かんばんの画面の問い合わせは、未完了の 4 つの列を希望納期と受注番号の昇順で、終わった 3 つの列を受注番号の降順で読む" do
    columns = GraphQL.parse(Rails.root.join("frontend/graphql/supplier/SupplierKanban.graphql").read).definitions.sole.selections.sole.selections
    open = [ "orderBy: {field: DUE_DATE, direction: ASC}", "thenBy: [{field: ORDER_NO, direction: ASC}]" ]
    done = [ "orderBy: {field: ORDER_NO, direction: DESC}" ]

    expect(columns.to_h { |column| [ column.alias, column.arguments.select { %w[orderBy thenBy].include?(_1.name) }.map(&:to_query_string) ] })
      .to eq("awaitingPartMatch" => open, "received" => open, "partiallyAllocated" => open, "allocated" => open,
        "shipped" => done, "inspected" => done, "cancelled" => done)
  end

  it "安全在庫を下回る在庫を、品目コードの昇順で上限の件数まで返す" do
    stub_const("Types::SupplierDashboardType::STOCKS_LIMIT", 2)
    stock_below("AXLE-1")

    expect(dashboard.fetch("stocksBelowSafetyStock").map { _1.dig("item", "code") }).to eq(%w[AXLE-1 BOLT-1])
  end
end
