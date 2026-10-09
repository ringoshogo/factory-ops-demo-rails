require "rails_helper"
require_relative "../support/events"

# 出荷指示と出荷実績の計上の入口。出荷可能になった受注に出荷依頼が現れ、有効な指示のある出荷依頼だけを計上できる
# （docs/architecture/graphql-schema.md「mutation の一覧」、docs/architecture/data-model.md「出荷（fulfillment）」）
RSpec.describe "出荷指示と出荷実績の計上", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant, name: "組立メーカー") }
  let(:member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code: "BOLT-8") } }
  let!(:order) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:sales_order, customer_tenant_id: buyer.id, due_date: Date.new(2026, 10, 31)).tap do
        FactoryBot.create(:sales_order_line, :matched, sales_order: _1, item_id: item.id, quantity: 5)
      end
    end
  end

  before do
    post "/session", params: { email: member.email, password: "password" }, as: :json
    expect(response).to have_http_status(:no_content)
  end

  def graphql(query, **variables)
    post "/graphql", params: { query:, variables: }, as: :json
    response.parsed_body
  end

  def mutate(name, **input)
    graphql(<<~GRAPHQL, input:).dig("data", name)
      mutation($input: #{name.camelize}Input!) {
        #{name}(input: $input) { shipmentRequest { status instruction { plannedDate } shipment { shippedOn lines { quantity } } } errors { code } }
      }
    GRAPHQL
  end

  # 入庫して全量を引き当て、出た「出荷可能」を出荷へ流す
  def make_ready
    graphql("mutation($input: AdjustStockInput!) { adjustStock(input: $input) { errors { code } } }",
      input: { itemId: item.id, type: "INBOUND", quantity: 8 })
    graphql("mutation($input: AllocateSalesOrderInput!) { allocateSalesOrder(input: $input) { errors { code } } }",
      input: { salesOrderId: order.id })
    deliver_enqueued_events
    graphql("{ supplier { shipmentRequests { nodes { id } } } }").dig("data", "supplier", "shipmentRequests", "nodes").sole["id"]
  end

  it "出荷可能になった受注に出荷依頼が現れ、指示を作って計上すると出荷済になり、在庫が減る" do
    expect(graphql("query($id: ID!) { supplier { salesOrder(id: $id) { shipmentRequest { id } } } }", id: order.id)
      .dig("data", "supplier", "salesOrder", "shipmentRequest")).to be_nil

    request_id = make_ready
    expect(graphql(<<~GRAPHQL, id: order.id).dig("data", "supplier", "salesOrder", "shipmentRequest"))
      query($id: ID!) {
        supplier { salesOrder(id: $id) { shipmentRequest {
          id status dueDate customer { name } salesOrder { id } instruction { plannedDate } shipment { id }
          lines { quantity item { code } salesOrderLine { allocatedQuantity } }
        } } }
      }
    GRAPHQL
      .to eq("id" => request_id, "status" => "READY", "dueDate" => "2026-10-31", "customer" => { "name" => "組立メーカー" },
        "salesOrder" => { "id" => order.id }, "instruction" => nil, "shipment" => nil,
        "lines" => [ { "quantity" => 5, "item" => { "code" => "BOLT-8" }, "salesOrderLine" => { "allocatedQuantity" => 5 } } ])

    expect(mutate("createShippingInstruction", shipmentRequestId: request_id, plannedDate: "2026-10-20"))
      .to eq("shipmentRequest" => { "status" => "INSTRUCTED", "instruction" => { "plannedDate" => "2026-10-20" }, "shipment" => nil },
        "errors" => [])
    expect(mutate("createShippingInstruction", shipmentRequestId: request_id, plannedDate: "2026-10-21"))
      .to eq("shipmentRequest" => nil, "errors" => [ { "code" => "CONFLICT" } ])

    expect(mutate("postShipment", shipmentRequestId: request_id, shippedOn: "2026-10-20"))
      .to eq("shipmentRequest" => { "status" => "SHIPPED", "instruction" => { "plannedDate" => "2026-10-20" },
        "shipment" => { "shippedOn" => "2026-10-20", "lines" => [ { "quantity" => 5 } ] } }, "errors" => [])
    expect(graphql("{ supplier { stocks { nodes { onHand allocated available } } } }").dig("data", "supplier", "stocks", "nodes"))
      .to eq([ { "onHand" => 3, "allocated" => 0, "available" => 3 } ])

    expect(mutate("postShipment", shipmentRequestId: request_id, shippedOn: "2026-10-20"))
      .to eq("shipmentRequest" => nil, "errors" => [ { "code" => "CONFLICT" } ])
    expect(mutate("cancelShippingInstruction", shipmentRequestId: request_id))
      .to eq("shipmentRequest" => nil, "errors" => [ { "code" => "CONFLICT" } ])
  end

  it "指示を取り消すと出荷待ちに戻り、有効な指示の無い出荷依頼は計上できない" do
    request_id = make_ready
    mutate("createShippingInstruction", shipmentRequestId: request_id, plannedDate: "2026-10-20")

    expect(mutate("cancelShippingInstruction", shipmentRequestId: request_id))
      .to eq("shipmentRequest" => { "status" => "READY", "instruction" => nil, "shipment" => nil }, "errors" => [])
    expect(mutate("postShipment", shipmentRequestId: request_id, shippedOn: "2026-10-20"))
      .to eq("shipmentRequest" => nil, "errors" => [ { "code" => "CONFLICT" } ])
  end
end
