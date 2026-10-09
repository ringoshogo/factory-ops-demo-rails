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

  def login_as(user)
    post "/session", params: { email: user.email, password: "password" }, as: :json
    expect(response).to have_http_status(:no_content)
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
end
