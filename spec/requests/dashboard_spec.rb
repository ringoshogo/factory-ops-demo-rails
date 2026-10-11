require "rails_helper"

# 受注側のダッシュボードの入口。画面の問い合わせの応答が、4 つの公開 API の集計と同じ値を返す
# （docs/architecture/graphql-schema.md「読み取りの一覧」）。集計の境界は、各公開 API の spec が確かめる
RSpec.describe "受注側のダッシュボード", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:actor) { Partnerships::Actor.new(user_id: member.id, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:screen) { Rails.root.join("spec/fixtures/graphql/screens/supplier_dashboard.graphql").read }
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

  it "安全在庫を下回る在庫を、品目コードの昇順で上限の件数まで返す" do
    stub_const("Types::SupplierDashboardType::STOCKS_LIMIT", 2)
    stock_below("AXLE-1")

    expect(dashboard.fetch("stocksBelowSafetyStock").map { _1.dig("item", "code") }).to eq(%w[AXLE-1 BOLT-1])
  end
end
