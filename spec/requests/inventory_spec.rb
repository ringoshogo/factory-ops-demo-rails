require "rails_helper"

# 在庫と引当の入口。入庫と引当が受注の状況・在庫・移動履歴に現れ、有効在庫を超える出庫は入力の誤りになる
# （docs/architecture/graphql-schema.md「mutation の一覧」、docs/architecture/data-model.md「在庫（`inventory`）」）
RSpec.describe "在庫と引当", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code: "BOLT-8") } }
  let!(:order) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:sales_order).tap { FactoryBot.create(:sales_order_line, :matched, sales_order: _1, item_id: item.id, quantity: 5) }
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

  def adjust(type, quantity, item_id: item.id)
    graphql(<<~GRAPHQL, input: { itemId: item_id, type:, quantity:, reason: "棚卸" }).dig("data", "adjustStock")
      mutation($input: AdjustStockInput!) {
        adjustStock(input: $input) { stock { item { code } onHand allocated available } errors { code path } }
      }
    GRAPHQL
  end

  def allocate
    graphql(<<~GRAPHQL, input: { salesOrderId: order.id }).dig("data", "allocateSalesOrder")
      mutation($input: AllocateSalesOrderInput!) {
        allocateSalesOrder(input: $input) { salesOrder { status lines { allocatedQuantity } } errors { code } }
      }
    GRAPHQL
  end

  it "入庫して引き当てると、受注の状況・明細の引当数量・品目の在庫・移動履歴に現れる" do
    expect(adjust("INBOUND", 3)).to eq("stock" => { "item" => { "code" => "BOLT-8" }, "onHand" => 3, "allocated" => 0,
      "available" => 3 }, "errors" => [])
    expect(allocate).to eq("salesOrder" => { "status" => "PARTIALLY_ALLOCATED", "lines" => [ { "allocatedQuantity" => 3 } ] },
      "errors" => [])

    adjust("INBOUND", 2)
    expect(allocate.dig("salesOrder", "status")).to eq("ALLOCATED")

    expect(graphql("{ supplier { items { nodes { stock { onHand allocated available belowSafetyStock } } } } }")
      .dig("data", "supplier", "items", "nodes")).to eq([ { "stock" => { "onHand" => 5, "allocated" => 5, "available" => 0,
        "belowSafetyStock" => false } } ])
    expect(graphql("query($id: ID) { supplier { stockMovements(itemId: $id) { nodes { type quantity reason } } } }", id: item.id)
      .dig("data", "supplier", "stockMovements", "nodes").map(&:values))
      .to eq([ [ "ALLOCATE", 2, nil ], [ "INBOUND", 2, "棚卸" ], [ "ALLOCATE", 3, nil ], [ "INBOUND", 3, "棚卸" ] ])
  end

  it "有効在庫を超える出庫は INVALID_INPUT、見えない品目は NOT_FOUND を返す" do
    adjust("INBOUND", 5)
    allocate

    expect(adjust("OUTBOUND", 1)).to eq("stock" => nil, "errors" => [ { "code" => "INVALID_INPUT", "path" => [ "quantity" ] } ])
    expect(adjust("INBOUND", 1, item_id: SecureRandom.uuid)).to eq("stock" => nil, "errors" => [ { "code" => "NOT_FOUND", "path" => nil } ])
  end

  it "入出庫も引当もしていない品目の在庫は空" do
    expect(graphql("{ supplier { items { nodes { stock { onHand } } } } }").dig("data", "supplier", "items", "nodes"))
      .to eq([ { "stock" => nil } ])
  end
end
