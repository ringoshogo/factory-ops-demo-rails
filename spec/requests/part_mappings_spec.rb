require "rails_helper"
require_relative "../support/events"

# 品番の対応表と照合のやり直し（docs/implementation-plan.md M11 の完了条件、docs/architecture/context-map.md「発注の連結と品番の照合」5）
RSpec.describe "品番の対応表と照合のやり直し", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant, name: "青嵐精機工業") }
  let!(:buyer) { FactoryBot.create(:tenant, name: "組立メーカー") }
  let(:supplier_member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }
  let!(:partnership) do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders]) }
  end
  let!(:bolt) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code: "BOLT-8", name: "六角ボルト M8", unit_price: 120) } }
  let!(:nut) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code: "NUT-8", name: "六角ナット M8", unit_price: 30) } }

  def login_as(user)
    post "/session", params: { email: user.email, password: "password" }, as: :json
    expect(response).to have_http_status(:no_content)
  end

  def graphql(query, **variables)
    post "/graphql", params: { query:, variables: }, as: :json
    response.parsed_body
  end

  # 発注側で発注し、受注側へ「発注登録」を流して受注を作る。発注 ID を返す
  def place_and_deliver(*part_numbers)
    login_as(buyer_member)
    placed = graphql(<<~GRAPHQL, input: { supplierTenantId: supplier.id, lines: part_numbers.map { { partNumber: _1, quantity: 2 } } })
      mutation($input: PlacePurchaseOrderInput!) { placePurchaseOrder(input: $input) { purchaseOrder { id } errors { code } } }
    GRAPHQL
    deliver_enqueued_events
    placed.dig("data", "placePurchaseOrder", "purchaseOrder", "id")
  end

  def register(customer_tenant_id: buyer.id, customer_part_number: "MY-BOLT", item_id: bolt.id)
    graphql(<<~GRAPHQL, input: { customerTenantId: customer_tenant_id, customerPartNumber: customer_part_number, itemId: item_id })
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
    graphql("{ supplier { salesOrders { nodes { status lines { customerPartNumber itemName unitPrice } } } } }")
      .dig("data", "supplier", "salesOrders", "nodes")
  end

  def purchase_order(id)
    graphql(<<~GRAPHQL, id:).dig("data", "buyer", "purchaseOrder")
      query($id: ID!) { buyer { purchaseOrder(id: $id) { status lines { partNumber confirmedItemName confirmedUnitPrice } } } }
    GRAPHQL
  end

  def part_mappings
    graphql("{ supplier { partMappings { nodes { customerPartNumber } } } }").dig("data", "supplier", "partMappings", "nodes")
  end

  def confirmed_events = enqueued_event_jobs.select { _1.arguments["arguments"].first == "Contracts::SalesOrderConfirmed" }

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

  it "照合できない明細が残る受注は確定せず、「受注確定」も出さない。最後の明細が照合できたときに 1 回だけ出す" do
    place_and_deliver("MY-BOLT", "MY-NUT")
    login_as(supplier_member)

    register
    expect(sales_orders).to match([ include("status" => "AWAITING_PART_MATCH",
      "lines" => [ include("itemName" => "六角ボルト M8"), include("customerPartNumber" => "MY-NUT", "itemName" => nil) ]) ])
    expect(confirmed_events).to be_empty

    register(customer_part_number: "MY-NUT", item_id: nut.id)
    expect(sales_orders).to match([ include("status" => "RECEIVED") ])
    # 品目を差し替えても、確定した受注は照合し直さない
    register(customer_part_number: "MY-NUT", item_id: bolt.id)
    expect(sales_orders).to match([ include("lines" => [ include("itemName" => "六角ボルト M8"), include("itemName" => "六角ナット M8") ]) ])
    expect(confirmed_events.size).to eq(1)
  end

  it "別の取引先の同じ品番の対応は、照合に使わない" do
    other_buyer = FactoryBot.create(:tenant)
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: other_buyer.id) }
    place_and_deliver("MY-BOLT")
    login_as(supplier_member)

    expect(register(customer_tenant_id: other_buyer.id)["errors"]).to eq([])
    expect(sales_orders).to match([ include("status" => "AWAITING_PART_MATCH") ])
  end

  it "失効した取引関係の相手にも登録でき、失効の前の発注が受注まで進む" do
    place_and_deliver("MY-BOLT")
    Tenancy.with_tenant(supplier.id) do
      admin = Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "admin", partner_code: "")
      Partnerships::Management.revoke(admin, partnership_id: partnership.id)
    end
    login_as(supplier_member)

    expect(register["errors"]).to eq([])
    expect(sales_orders).to match([ include("status" => "RECEIVED") ])
  end

  it "見えない品目と、取引関係の無い相手は NOT_FOUND で、対応表に何も残さない" do
    stranger = FactoryBot.create(:tenant)
    others_item = Tenancy.with_tenant(stranger.id) { FactoryBot.create(:item) }
    login_as(supplier_member)

    expect(register(item_id: others_item.id)).to eq("partMapping" => nil, "errors" => [ { "code" => "NOT_FOUND", "path" => [ "itemId" ] } ])
    [ stranger.id, SecureRandom.uuid ].each do |customer_tenant_id|
      expect(register(customer_tenant_id:)["errors"]).to eq([ { "code" => "NOT_FOUND", "path" => [ "customerTenantId" ] } ])
    end
    expect(register(customer_part_number: "")["errors"]).to match([ include("code" => "INVALID_INPUT", "path" => [ "customerPartNumber" ]) ])
    expect(part_mappings).to eq([])
  end
end
