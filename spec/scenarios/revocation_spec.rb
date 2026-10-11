require "rails_helper"
require_relative "../support/scenarios"

# 取引関係の失効（docs/guides/testing.md「重要シナリオ」S2、docs/architecture/context-map.md「取引関係の失効」）。
# 失効で相手のデータを読む 3 経路と新しい発注が閉じ、受注確定まで進んだ取引は、引当・出荷・検収・締め・確定と進み、
# 発注側に受領請求書が届く
RSpec.describe "取引関係の失効", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant, name: "青嵐精機工業") }
  let!(:buyer) { FactoryBot.create(:tenant, name: "組立メーカー") }
  let(:supplier_admin) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) } }
  let(:buyer_admin) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user, :admin) } }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }

  def place(quantity)
    mutate("placePurchaseOrder", "purchaseOrder { id } errors { code }", supplierTenantId: supplier.id,
      lines: [ { partNumber: "MY-BOLT", quantity: } ])
  end

  def purchase_order(id)
    query(<<~GRAPHQL, id:).dig("buyer", "purchaseOrder")
      query($id: ID!) { buyer { purchaseOrder(id: $id) {
        status inboundShipments { id lines { id shippedQuantity } } supplierShipments { shippedOn }
      } } }
    GRAPHQL
  end

  # 発注側から見た 3 経路。経路 1 は取引先を 1 社選んで引くカタログ、経路 2 は取引先の一覧、経路 3 は自社の発注に連結した出荷
  def partner_reads(purchase_order_id)
    { catalog: query("query($id: ID!) { buyer { supplier(supplierTenantId: $id) { catalog { nodes { code } } } } }", id: supplier.id)
        .dig("buyer", "supplier", "catalog", "nodes"),
      suppliers: query("{ buyer { suppliers { supplier { name } } } }").dig("buyer", "suppliers"),
      shipments: purchase_order(purchase_order_id).fetch("supplierShipments") }
  end

  # 受注側が、発注に連結した受注を全量で引き当て、出荷指示を作って計上する
  def ship(sales_order_id)
    mutate!("allocateSalesOrder", "salesOrder { id }", salesOrderId: sales_order_id)
    deliver_enqueued_events
    request_id = query("{ supplier { shipmentRequests { nodes { id salesOrder { id } } } } }").dig("supplier", "shipmentRequests", "nodes")
      .find { _1.dig("salesOrder", "id") == sales_order_id }.fetch("id")
    mutate!("createShippingInstruction", "shipmentRequest { id }", shipmentRequestId: request_id, plannedDate: Date.current.iso8601)
    mutate!("postShipment", "shipmentRequest { id }", shipmentRequestId: request_id, shippedOn: Date.current.iso8601)
    deliver_enqueued_events
  end

  it "失効で 3 経路と新しい発注が閉じ、受注確定まで進んだ取引は請求まで進んで、発注側に受領請求書が届く" do
    login_as(supplier_admin)
    partnership_id = mutate!("establishPartnership", "partnership { id }", partnerCode: buyer.partner_code).dig("partnership", "id")
    %w[PLACE_ORDERS VIEW_CATALOG VIEW_SHIPMENTS].each do |permission|
      mutate!("grantPermission", "partnership { id }", partnershipId: partnership_id, permission:)
    end
    item_id = mutate!("saveItem", "item { id }", code: "BOLT", name: "六角ボルト", unit: "本", unitPrice: "120", taxRatePercent: 10)
      .dig("item", "id")
    mutate!("setItemPublished", "item { id }", itemId: item_id, published: true)
    mutate!("registerPartMapping", "partMapping { id }", customerTenantId: buyer.id, customerPartNumber: "MY-BOLT", itemId: item_id)
    mutate!("adjustStock", "stock { onHand }", itemId: item_id, type: "INBOUND", quantity: 10)

    # 経路 3 の対照に使う発注（失効の前に出荷まで進める）と、失効の後に請求まで進める発注を出す
    login_as(buyer_member)
    shipped_order_id, open_order_id = [ 2, 3 ].map { place(_1).dig("purchaseOrder", "id") }
    deliver_enqueued_events

    login_as(supplier_admin)
    sales_orders = query("{ supplier { salesOrders { nodes { id status lines { quantity } } } } }").dig("supplier", "salesOrders", "nodes")
    expect(sales_orders.map { _1.fetch("status") }).to eq(%w[RECEIVED RECEIVED])
    shipped_sales_order_id, open_sales_order_id = [ 2, 3 ].map { |quantity| sales_orders.find { _1.dig("lines", 0, "quantity") == quantity }.fetch("id") }
    ship(shipped_sales_order_id)

    # 対照：失効の前は、3 経路のどれも相手のデータを返し、受注確定の写しで発注は受注済になっている
    login_as(buyer_member)
    expect(partner_reads(shipped_order_id)).to eq(catalog: [ { "code" => "BOLT" } ], suppliers: [ { "supplier" => { "name" => "青嵐精機工業" } } ],
      shipments: [ { "shippedOn" => Date.current.iso8601 } ])
    expect(purchase_order(open_order_id).fetch("status")).to eq("ACCEPTED")

    login_as(supplier_admin)
    mutate!("revokePartnership", "partnership { status }", partnershipId: partnership_id)

    # 失効の後は、3 経路が閉じ、新しい発注は相手の有無を明かさない NOT_PERMITTED になる。自社の入荷の写しは残る
    login_as(buyer_member)
    expect(query("query($id: ID!) { buyer { supplier(supplierTenantId: $id) { supplier { name } } } }", id: supplier.id)
      .dig("buyer", "supplier")).to be_nil
    expect(partner_reads(shipped_order_id).except(:catalog)).to eq(suppliers: [], shipments: [])
    expect(purchase_order(shipped_order_id).fetch("inboundShipments").size).to eq(1)
    expect(place(1)).to eq("purchaseOrder" => nil, "errors" => [ { "code" => "NOT_PERMITTED" } ])
    expect(enqueued_payloads("Contracts::PurchaseOrderPlaced")).to eq([])

    # 受注確定まで進んだ取引は、失効の後も引当・出荷・検収・締め・確定と進む
    login_as(supplier_admin)
    ship(open_sales_order_id)

    login_as(buyer_admin)
    inbound = purchase_order(open_order_id).fetch("inboundShipments").sole
    mutate!("inspectInboundShipment", "purchaseOrder { id }", inboundShipmentId: inbound.fetch("id"),
      lines: inbound.fetch("lines").map { { inboundShipmentLineId: _1.fetch("id"), acceptedQuantity: _1.fetch("shippedQuantity") } })
    deliver_enqueued_events

    login_as(supplier_admin)
    mutate!("setBillingTerm", "billingTerm { closingDay }", customerTenantId: buyer.id, closingDay: 31)
    invoice_id = mutate!("closeBillingPeriod", "invoice { id }", customerTenantId: buyer.id,
      closingDate: Date.current.end_of_month.iso8601).dig("invoice", "id")
    mutate!("issueInvoice", "invoice { id }", invoiceId: invoice_id)
    deliver_enqueued_events

    login_as(buyer_member)
    expect(purchase_order(open_order_id).fetch("status")).to eq("INSPECTED")
    received = query("{ buyer { receivedInvoices { nodes { invoiceNumber supplier { name } total lines { quantity amount } } } } }")
      .dig("buyer", "receivedInvoices", "nodes")
    expect(received).to eq([ { "invoiceNumber" => "INV-000001", "supplier" => { "name" => "青嵐精機工業" }, "total" => "396",
      "lines" => [ { "quantity" => 3, "amount" => "360" } ] } ])
  end
end
