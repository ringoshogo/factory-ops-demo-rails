require "rails_helper"
require_relative "../support/events"

# 出荷計上の還流と経路 3。出荷計上で受注と発注の状況が進み、発注側は経路 3 の出荷を付与と取引関係がある間だけ読む。
# 自社の入荷の写しは、経路 3 が閉じても残る（docs/architecture/graphql-schema.md「発注側の視点」）
RSpec.describe "出荷計上の還流と経路 3", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:supplier_member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }
  let!(:partnership) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders view_shipments])
    end
  end
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code: "BOLT-8") } }
  let!(:mapping) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:customer_part_mapping, customer_tenant_id: buyer.id, customer_part_number: "MY-BOLT", item:)
    end
  end

  def graphql(query, **variables)
    post "/graphql", params: { query:, variables: }, as: :json
    response.parsed_body.tap { expect(_1["errors"]).to be_nil }
  end

  def mutate(name, **input)
    graphql("mutation($input: #{name.camelize}Input!) { #{name}(input: $input) { errors { code } } }", input:)
      .dig("data", name, "errors").tap { expect(_1).to eq([]) }
  end

  def change_partnership(name, **args)
    Tenancy.with_tenant(supplier.id) do
      actor = Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "admin", partner_code: "")
      Partnerships::Management.public_send(name, actor, partnership_id: partnership.id, **args)
    end
  end

  # 発注側が発注し、受注側が全量を引き当てて計上し、出たイベントを流し終えた発注の ID
  let!(:purchase_order_id) do
    login_as(buyer_member)
    id = graphql(<<~GRAPHQL, input: { supplierTenantId: supplier.id, lines: [ { partNumber: "MY-BOLT", quantity: 5 } ] })
      mutation($input: PlacePurchaseOrderInput!) { placePurchaseOrder(input: $input) { purchaseOrder { id } } }
    GRAPHQL
      .dig("data", "placePurchaseOrder", "purchaseOrder", "id")
    deliver_enqueued_events

    login_as(supplier_member)
    sales_order_id = graphql("{ supplier { salesOrders { nodes { id } } } }").dig("data", "supplier", "salesOrders", "nodes").sole["id"]
    mutate("adjustStock", itemId: item.id, type: "INBOUND", quantity: 5)
    mutate("allocateSalesOrder", salesOrderId: sales_order_id)
    deliver_enqueued_events
    request_id = graphql("{ supplier { shipmentRequests { nodes { id } } } }").dig("data", "supplier", "shipmentRequests", "nodes").sole["id"]
    mutate("createShippingInstruction", shipmentRequestId: request_id, plannedDate: "2026-10-09")
    mutate("postShipment", shipmentRequestId: request_id, shippedOn: "2026-10-09")
    deliver_enqueued_events
    id
  end

  def purchase_order
    graphql(<<~GRAPHQL, id: purchase_order_id).dig("data", "buyer", "purchaseOrder")
      query($id: ID!) {
        buyer { purchaseOrder(id: $id) {
          status
          inboundShipments { shippedOn lines { shippedQuantity purchaseOrderLine { partNumber } } }
          supplierShipments { shippedOn lines { quantity purchaseOrderLine { partNumber } } }
        } }
      }
    GRAPHQL
  end

  let(:shipped) { { "shippedOn" => "2026-10-09" } }

  it "出荷計上で受注は出荷済に、発注は入荷予定になり、発注側は入荷の写しと経路 3 の出荷を自社の発注明細で読める" do
    expect(graphql("{ supplier { salesOrders { nodes { status } } } }").dig("data", "supplier", "salesOrders", "nodes"))
      .to eq([ { "status" => "SHIPPED" } ])

    login_as(buyer_member)
    expect(purchase_order).to eq(
      "status" => "INBOUND",
      "inboundShipments" => [ shipped.merge("lines" => [ { "shippedQuantity" => 5, "purchaseOrderLine" => { "partNumber" => "MY-BOLT" } } ]) ],
      "supplierShipments" => [ shipped.merge("lines" => [ { "quantity" => 5, "purchaseOrderLine" => { "partNumber" => "MY-BOLT" } } ]) ]
    )
  end

  it "受注側の出荷実績・出荷明細の ID を、どちらの型でも返さない" do
    shipment = graphql("{ supplier { shipmentRequests { nodes { shipment { id lines { id } } } } } }")
      .dig("data", "supplier", "shipmentRequests", "nodes").sole["shipment"]
    ids = [ shipment["id"], *shipment["lines"].pluck("id") ]
    login_as(buyer_member)
    purchase_order

    expect(ids.size).to eq(2)
    ids.each { expect(response.body).not_to include(_1) }
  end

  it "view_shipments を撤回すると経路 3 は空になり、自社の入荷の写しは残る" do
    change_partnership(:withdraw, permission: "view_shipments")
    login_as(buyer_member)

    expect(purchase_order).to include("status" => "INBOUND", "supplierShipments" => [])
    expect(purchase_order["inboundShipments"].size).to eq(1)
  end

  it "取引関係を失効させると、付与が残っていても経路 3 は空になり、自社の入荷の写しは残る" do
    change_partnership(:revoke)
    login_as(buyer_member)

    expect(purchase_order).to include("status" => "INBOUND", "supplierShipments" => [])
    expect(purchase_order["inboundShipments"].size).to eq(1)
  end

  # 1 件ずつのページで最後までたどった出荷依頼の ID。並べ替えを受け付けなければ、data が無く nil を返す
  def request_ids(order_by)
    query = <<~GRAPHQL
      query($after: String, $orderBy: ShipmentRequestOrder) {
        supplier { shipmentRequests(first: 1, after: $after, orderBy: $orderBy) { nodes { id } pageInfo { hasNextPage endCursor } } }
      }
    GRAPHQL
    ids = []
    after = nil
    loop do
      post "/graphql", params: { query:, variables: { after:, orderBy: order_by } }, as: :json
      page = response.parsed_body.dig("data", "supplier", "shipmentRequests")
      break unless page

      ids.concat(page.fetch("nodes").map { _1["id"] })
      break ids unless page.dig("pageInfo", "hasNextPage")

      after = page.dig("pageInfo", "endCursor")
    end
  end

  # 計上まで流した出荷依頼（受注番号 SO-000001、出荷予定日 2026-10-09）の受注番号は、「出荷可能」のイベントで写したものである
  it "受注番号の写しで並べ、そのカーソルで続きを返す" do
    flowed = graphql("{ supplier { shipmentRequests { nodes { id salesOrder { orderNo } } } } }")
      .dig("data", "supplier", "shipmentRequests", "nodes").sole
    expect(flowed.dig("salesOrder", "orderNo")).to eq("SO-000001")
    later, earlier = Tenancy.with_tenant(supplier.id) { %w[SO-000009 SO-000000].map { FactoryBot.create(:shipment_request, sales_order_no: _1) } }

    expect(request_ids({ field: "ORDER_NO", direction: "ASC" })).to eq([ earlier.id, flowed["id"], later.id ])
    expect(request_ids({ field: "ORDER_NO", direction: "DESC" })).to eq([ later.id, flowed["id"], earlier.id ])
  end

  # 出荷予定日は有効な出荷指示の値で、取り消した指示しか無い出荷依頼は空として最後に並ぶ
  it "有効な出荷指示の出荷予定日で並べ、指示の無い出荷依頼を最後に置き、そのカーソルで続きを返す" do
    flowed = graphql("{ supplier { shipmentRequests { nodes { id } } } }").dig("data", "supplier", "shipmentRequests", "nodes").sole["id"]
    early, late, cancelled = Tenancy.with_tenant(supplier.id) do
      [ Date.new(2026, 10, 1), Date.new(2026, 10, 20), Date.new(2026, 10, 2) ].map do |planned_date|
        FactoryBot.create(:shipping_instruction, planned_date:).shipment_request
      end.tap { |requests| requests.last.instructions.sole.update!(status: "cancelled") }
    end

    expect(request_ids({ field: "PLANNED_DATE", direction: "ASC" })).to eq([ early.id, flowed, late.id, cancelled.id ])
    expect(request_ids({ field: "PLANNED_DATE", direction: "DESC" })).to eq([ late.id, flowed, early.id, cancelled.id ])
  end
end
