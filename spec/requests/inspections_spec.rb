require "rails_helper"
require_relative "../support/events"

# 発注側の検収と、受注側の検収済・請求対象明細の通し（docs/architecture/context-map.md「検収と請求の流れ」1〜4）
RSpec.describe "検収", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:supplier_admin) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) } }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }

  def login_as(user)
    post "/session", params: { email: user.email, password: "password" }, as: :json
    expect(response).to have_http_status(:no_content)
  end

  def graphql(query, **variables)
    post "/graphql", params: { query:, variables: }, as: :json
    expect(response.parsed_body["errors"]).to be_nil
    response.parsed_body.fetch("data")
  end

  def mutate(name, selection, **input)
    graphql(<<~GRAPHQL, input:).fetch(name)
      mutation($input: #{name[0].upcase}#{name[1..]}Input!) { #{name}(input: $input) { #{selection} errors { code path } } }
    GRAPHQL
  end

  def inbound_selection = "status inboundShipments { id inspection { inspectedOn } lines { id shippedQuantity acceptedQuantity } }"

  def purchase_order
    graphql(<<~GRAPHQL, id: @purchase_order_id).dig("buyer", "purchaseOrder")
      query($id: ID!) { buyer { purchaseOrder(id: $id) { #{inbound_selection} } } }
    GRAPHQL
  end

  def sales_order_status
    graphql("query($id: ID!) { supplier { salesOrder(id: $id) { status } } }", id: @sales_order_id).dig("supplier", "salesOrder", "status")
  end

  def inspect_inbound(lines)
    mutate("inspectInboundShipment", "purchaseOrder { #{inbound_selection} }", inboundShipmentId: @inbound_id, lines:)
  end

  # 取引関係と品目・対応表・在庫を整え、2 明細の発注から受注・引当・出荷指示・出荷計上まで進め、発注側に入荷を届ける
  before do
    login_as(supplier_admin)
    partnership_id = mutate("establishPartnership", "partnership { id }", partnerCode: buyer.partner_code).dig("partnership", "id")
    mutate("grantPermission", "partnership { id }", partnershipId: partnership_id, permission: "PLACE_ORDERS")
    %w[BOLT NUT].each do |code|
      item_id = mutate("saveItem", "item { id }", code:, name: code, unit: "本", unitPrice: "120").dig("item", "id")
      mutate("registerPartMapping", "partMapping { id }", customerTenantId: buyer.id, customerPartNumber: "MY-#{code}", itemId: item_id)
      mutate("adjustStock", "stock { onHand }", itemId: item_id, type: "INBOUND", quantity: 10)
    end

    login_as(buyer_member)
    @purchase_order_id = mutate("placePurchaseOrder", "purchaseOrder { id }", supplierTenantId: supplier.id,
      lines: [ { partNumber: "MY-BOLT", quantity: 4 }, { partNumber: "MY-NUT", quantity: 2 } ]).dig("purchaseOrder", "id")
    deliver_enqueued_events

    login_as(supplier_admin)
    @sales_order_id = graphql("{ supplier { salesOrders { nodes { id } } } }").dig("supplier", "salesOrders", "nodes").sole["id"]
    mutate("allocateSalesOrder", "salesOrder { id }", salesOrderId: @sales_order_id)
    deliver_enqueued_events
    request_id = graphql("{ supplier { shipmentRequests { nodes { id } } } }").dig("supplier", "shipmentRequests", "nodes").sole["id"]
    mutate("createShippingInstruction", "shipmentRequest { id }", shipmentRequestId: request_id, plannedDate: "2026-10-20")
    mutate("postShipment", "shipmentRequest { id }", shipmentRequestId: request_id, shippedOn: "2026-10-20")
    deliver_enqueued_events
    expect(sales_order_status).to eq("SHIPPED")

    login_as(buyer_member)
    inbound = purchase_order.fetch("inboundShipments").sole
    @inbound_id = inbound.fetch("id")
    @bolt_line_id, @nut_line_id = inbound.fetch("lines").sort_by { -_1.fetch("shippedQuantity") }.map { _1.fetch("id") }
  end

  it "検収前の入荷は検収と検収数量が空で、発注は入荷予定" do
    expect(purchase_order).to match("status" => "INBOUND", "inboundShipments" => [
      { "id" => @inbound_id, "inspection" => nil, "lines" => contain_exactly(
        { "id" => @bolt_line_id, "shippedQuantity" => 4, "acceptedQuantity" => nil },
        { "id" => @nut_line_id, "shippedQuantity" => 2, "acceptedQuantity" => nil }
      ) }
    ])
  end

  it "検収すると発注が検収済になり、監査の行が残り、イベントを流すと受注が検収済になる" do
    payload = inspect_inbound([ { inboundShipmentLineId: @bolt_line_id, acceptedQuantity: 3 },
                                { inboundShipmentLineId: @nut_line_id, acceptedQuantity: 0 } ])

    expect(payload).to match("errors" => [], "purchaseOrder" => { "status" => "INSPECTED", "inboundShipments" => [
      { "id" => @inbound_id, "inspection" => { "inspectedOn" => Date.current.iso8601 }, "lines" => contain_exactly(
        { "id" => @bolt_line_id, "shippedQuantity" => 4, "acceptedQuantity" => 3 },
        { "id" => @nut_line_id, "shippedQuantity" => 2, "acceptedQuantity" => 0 }
      ) }
    ] })
    expect(Tenancy.with_tenant(buyer.id) { AuditLog.where(action: "inbound_shipment.inspect").pluck(:actor_user_id, :target_type, :target_id, :counterparty_tenant_id) })
      .to eq([ [ buyer_member.id, "InboundShipment", @inbound_id, supplier.id ] ])

    deliver_enqueued_events
    login_as(supplier_admin)
    expect(sales_order_status).to eq("INSPECTED")
  end

  it "検収してイベントを流すと、受注側に検収数量が正の受注明細ごとの未請求の請求対象明細ができる" do
    inspect_inbound([ { inboundShipmentLineId: @bolt_line_id, acceptedQuantity: 3 }, { inboundShipmentLineId: @nut_line_id, acceptedQuantity: 0 } ])
    deliver_enqueued_events

    login_as(supplier_admin)
    expect(graphql("{ supplier { billableItems { nodes { itemName unitPrice quantity taxRatePercent amount inspectedOn } } } }"))
      .to eq("supplier" => { "billableItems" => { "nodes" => [
        { "itemName" => "BOLT", "unitPrice" => "120", "quantity" => 3, "taxRatePercent" => 10, "amount" => "360",
          "inspectedOn" => Date.current.iso8601 }
      ] } })
  end

  it "入力の誤りは INVALID_INPUT に写って誤りの明細を指し、2 回目の検収は CONFLICT に写る" do
    expect(inspect_inbound([ { inboundShipmentLineId: @bolt_line_id, acceptedQuantity: 3 },
                             { inboundShipmentLineId: @nut_line_id, acceptedQuantity: 3 } ]))
      .to eq("purchaseOrder" => nil, "errors" => [ { "code" => "INVALID_INPUT", "path" => [ "lines", "1", "acceptedQuantity" ] } ])

    lines = [ { inboundShipmentLineId: @bolt_line_id, acceptedQuantity: 4 }, { inboundShipmentLineId: @nut_line_id, acceptedQuantity: 2 } ]
    expect(inspect_inbound(lines)).to include("errors" => [])
    expect(inspect_inbound(lines)).to eq("purchaseOrder" => nil, "errors" => [ { "code" => "CONFLICT", "path" => nil } ])
    expect(Tenancy.with_tenant(buyer.id) { AuditLog.where(action: "inbound_shipment.inspect").count }).to eq(1)
  end
end
