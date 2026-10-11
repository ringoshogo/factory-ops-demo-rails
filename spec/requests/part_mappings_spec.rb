require "rails_helper"
require_relative "../support/events"

# 品番の対応表と照合のやり直し。対応表に登録すると、その取引先の照合待ちの受注を照合し直し、全明細が照合できた受注だけを確定する
# （docs/architecture/context-map.md「発注の連結と品番の照合」手順 5）
RSpec.describe "品番の対応表と照合のやり直し", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant, name: "青嵐精機工業") }
  let!(:buyer) { FactoryBot.create(:tenant, name: "組立メーカー") }
  let(:supplier_member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }
  let!(:partnership) do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders]) }
  end
  let!(:bolt) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code: "BOLT-8", name: "六角ボルト M8", unit_price: 120) } }

  # 発注側で発注し、受注側へ「発注登録」を流して受注を作る。発注 ID を返す
  def place_and_deliver(*part_numbers)
    login_as(buyer_member)
    placed = graphql_body(<<~GRAPHQL, input: { supplierTenantId: supplier.id, lines: part_numbers.map { { partNumber: _1, quantity: 2 } } })
      mutation($input: PlacePurchaseOrderInput!) { placePurchaseOrder(input: $input) { purchaseOrder { id } errors { code } } }
    GRAPHQL
    deliver_enqueued_events
    placed.dig("data", "placePurchaseOrder", "purchaseOrder", "id")
  end

  def register(customer_tenant_id: buyer.id, customer_part_number: "MY-BOLT", item_id: bolt.id)
    graphql_body(<<~GRAPHQL, input: { customerTenantId: customer_tenant_id, customerPartNumber: customer_part_number, itemId: item_id })
      mutation($input: RegisterPartMappingInput!) {
        registerPartMapping(input: $input) {
          partMapping { customer { name } customerPartNumber item { code } }
          errors { code path }
        }
      }
    GRAPHQL
      .dig("data", "registerPartMapping")
  end

  def sales_orders
    graphql_body("{ supplier { salesOrders { nodes { status lines { customerPartNumber itemName unitPrice } } } } }")
      .dig("data", "supplier", "salesOrders", "nodes")
  end

  def purchase_order(id)
    graphql_body(<<~GRAPHQL, id:).dig("data", "buyer", "purchaseOrder")
      query($id: ID!) { buyer { purchaseOrder(id: $id) { status lines { partNumber confirmedItemName confirmedUnitPrice } } } }
    GRAPHQL
  end

  def part_mappings
    graphql_body("{ supplier { partMappings { nodes { customerPartNumber } } } }").dig("data", "supplier", "partMappings", "nodes")
  end

  it "照合待ち → 対応表の登録 → 受注確定 → 発注が「受注済」になる" do
    purchase_order_id = place_and_deliver("MY-BOLT")
    login_as(supplier_member)
    expect(sales_orders).to match([ include("status" => "AWAITING_PART_MATCH") ])

    expect(register).to eq("partMapping" => { "customer" => { "name" => "組立メーカー" }, "customerPartNumber" => "MY-BOLT",
      "item" => { "code" => "BOLT-8" } }, "errors" => [])
    expect(sales_orders).to eq([ { "status" => "RECEIVED",
      "lines" => [ { "customerPartNumber" => "MY-BOLT", "itemName" => "六角ボルト M8", "unitPrice" => "120" } ] } ])
    expect(part_mappings).to eq([ { "customerPartNumber" => "MY-BOLT" } ])

    deliver_enqueued_events
    login_as(buyer_member)
    expect(purchase_order(purchase_order_id)).to eq("status" => "ACCEPTED",
      "lines" => [ { "partNumber" => "MY-BOLT", "confirmedItemName" => "六角ボルト M8", "confirmedUnitPrice" => "120" } ])
    # 発注側の対応表の一覧は自社の行だけで、受注側の対応表は見えない
    expect(part_mappings).to eq([])
  end

  # 照合の分岐と、取引先・品番の誤りは Sales::PartMappings の spec が確かめる。相手テナントの ID は S1 が確かめる
  it "見えない品目は、itemId を指す NOT_FOUND のユーザーエラーで、対応表に何も残さない" do
    stranger = FactoryBot.create(:tenant)
    others_item = Tenancy.with_tenant(stranger.id) { FactoryBot.create(:item) }
    login_as(supplier_member)

    expect(register(item_id: others_item.id)).to eq("partMapping" => nil, "errors" => [ { "code" => "NOT_FOUND", "path" => [ "itemId" ] } ])
    expect(part_mappings).to eq([])
  end
end
