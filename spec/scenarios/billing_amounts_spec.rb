require "rails_helper"
require_relative "../support/scenarios"

# 請求の金額と税の丸め（docs/guides/testing.md「重要シナリオ」S5、docs/architecture/context-map.md「検収と請求の流れ」）。
# 発注 → 受注 → 出荷 → 検収 → 締め → 確定 → 受領請求書で、単価・数量・税額・合計が 2 社で一致し、
# 税が請求書・税率ごとに 1 回だけ切り捨てられる
RSpec.describe "請求の金額と税の丸め", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant, name: "青嵐精機工業") }
  let!(:buyer) { FactoryBot.create(:tenant, name: "組立メーカー") }
  let(:supplier_admin) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) } }
  let(:buyer_admin) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user, :admin) } }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }

  # 品目ごとの単価・税率と、発注する数量。同じ税率の明細を 2 つずつ並べ、明細ごとに丸めると請求書の税額と食い違うようにする。
  # 10% は 315 円と 105 円で、明細ごとなら 31 + 10 = 41 円、まとめると 42 円。
  # 8% は 198 円と 99 円で、明細ごとなら 15 + 7 = 22 円、まとめると 297 × 0.08 = 23.76 → 23 円
  ITEMS = {
    "BOLT" => { unit_price: 105, tax_rate_percent: 10, quantity: 3 },
    "WASHER" => { unit_price: 105, tax_rate_percent: 10, quantity: 1 },
    "NUT" => { unit_price: 99, tax_rate_percent: 8, quantity: 2 },
    "PIN" => { unit_price: 99, tax_rate_percent: 8, quantity: 1 }
  }.freeze

  def line_amounts(lines) = lines.map { _1.slice("itemName", "unitPrice", "quantity", "taxRatePercent", "amount") }

  it "2 社の請求の金額が明細から合計まで一致し、税は請求書・税率ごとに 1 回だけ切り捨てられる" do
    login_as(supplier_admin)
    partnership_id = mutate!("establishPartnership", "partnership { id }", partnerCode: buyer.partner_code).dig("partnership", "id")
    mutate!("grantPermission", "partnership { id }", partnershipId: partnership_id, permission: "PLACE_ORDERS")
    ITEMS.each do |code, item|
      item_id = mutate!("saveItem", "item { id }", code:, name: code, unit: "本", unitPrice: item[:unit_price].to_s,
        taxRatePercent: item[:tax_rate_percent]).dig("item", "id")
      mutate!("registerPartMapping", "partMapping { id }", customerTenantId: buyer.id, customerPartNumber: "MY-#{code}", itemId: item_id)
      mutate!("adjustStock", "stock { onHand }", itemId: item_id, type: "INBOUND", quantity: 10)
    end

    # 発注は日常の業務なので member が登録する
    login_as(buyer_member)
    purchase_order_id = mutate!("placePurchaseOrder", "purchaseOrder { id }", supplierTenantId: supplier.id,
      lines: ITEMS.map { |code, item| { partNumber: "MY-#{code}", quantity: item[:quantity] } }).dig("purchaseOrder", "id")
    deliver_enqueued_events

    login_as(supplier_admin)
    sales_order_id = query("{ supplier { salesOrders { nodes { id } } } }").dig("supplier", "salesOrders", "nodes").sole.fetch("id")
    mutate!("allocateSalesOrder", "salesOrder { id }", salesOrderId: sales_order_id)
    deliver_enqueued_events
    request_id = query("{ supplier { shipmentRequests { nodes { id } } } }").dig("supplier", "shipmentRequests", "nodes").sole.fetch("id")
    mutate!("createShippingInstruction", "shipmentRequest { id }", shipmentRequestId: request_id, plannedDate: Date.current.iso8601)
    mutate!("postShipment", "shipmentRequest { id }", shipmentRequestId: request_id, shippedOn: Date.current.iso8601)
    deliver_enqueued_events

    # 検収は金額を確定させる操作なので admin が行う
    login_as(buyer_admin)
    inbound = query("query($id: ID!) { buyer { purchaseOrder(id: $id) { inboundShipments { id lines { id shippedQuantity } } } } }",
      id: purchase_order_id).dig("buyer", "purchaseOrder", "inboundShipments").sole
    mutate!("inspectInboundShipment", "purchaseOrder { id }", inboundShipmentId: inbound.fetch("id"),
      lines: inbound.fetch("lines").map { { inboundShipmentLineId: _1.fetch("id"), acceptedQuantity: _1.fetch("shippedQuantity") } })
    deliver_enqueued_events

    login_as(supplier_admin)
    mutate!("setBillingTerm", "billingTerm { closingDay }", customerTenantId: buyer.id, closingDay: 31)
    invoice_id = mutate!("closeBillingPeriod", "invoice { id }", customerTenantId: buyer.id,
      closingDate: Date.current.end_of_month.iso8601).dig("invoice", "id")
    mutate!("issueInvoice", "invoice { id }", invoiceId: invoice_id)
    invoice = query(<<~GRAPHQL, id: invoice_id).dig("supplier", "invoice")
      query($id: ID!) { supplier { invoice(id: $id) {
        invoiceNumber state subtotal taxTotal total taxSummaries { taxRatePercent taxableAmount taxAmount }
        items { nodes { itemName unitPrice quantity taxRatePercent amount } }
      } } }
    GRAPHQL
    deliver_enqueued_events

    login_as(buyer_member)
    received = query(<<~GRAPHQL).dig("buyer", "receivedInvoices", "nodes").sole
      { buyer { receivedInvoices { nodes {
        invoiceNumber supplier { name } subtotal taxTotal total lines { itemName unitPrice quantity taxRatePercent amount }
      } } } }
    GRAPHQL

    expected_lines = ITEMS.map do |code, item|
      { "itemName" => code, "unitPrice" => item[:unit_price].to_s, "quantity" => item[:quantity],
        "taxRatePercent" => item[:tax_rate_percent], "amount" => (item[:unit_price] * item[:quantity]).to_s }
    end
    expect(line_amounts(invoice.dig("items", "nodes"))).to match_array(expected_lines)
    expect(line_amounts(received.fetch("lines"))).to match_array(expected_lines)

    expect(invoice).to include("invoiceNumber" => "INV-000001", "state" => "ISSUED", "subtotal" => "717", "taxTotal" => "65",
      "total" => "782", "taxSummaries" => [ { "taxRatePercent" => 8, "taxableAmount" => "297", "taxAmount" => "23" },
                                            { "taxRatePercent" => 10, "taxableAmount" => "420", "taxAmount" => "42" } ])
    expect(received).to eq("invoiceNumber" => "INV-000001", "supplier" => { "name" => "青嵐精機工業" }, "subtotal" => "717",
      "taxTotal" => "65", "total" => "782", "lines" => received.fetch("lines"))
    # 明細ごとに切り捨てて足すと 63 円になり、請求書の税額と食い違う
    per_line_tax = ITEMS.values.sum { _1[:unit_price] * _1[:quantity] * _1[:tax_rate_percent] / 100 }
    expect(per_line_tax).to eq(63)
  end
end
