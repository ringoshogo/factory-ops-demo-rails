require "rails_helper"
require_relative "../support/scenarios"

# 発注と受注の連結（docs/guides/testing.md「重要シナリオ」S3、docs/architecture/context-map.md「発注の連結と品番の照合」）。
# 品番の照合待ち → 対応表の登録 → 受注確定の道を、同じイベントを 2 回流しても、届く順を入れ替えても、
# 受注は 1 件で、発注の状況は同じになる
RSpec.describe "発注と受注の連結", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant, name: "組立メーカー") }
  let(:supplier_admin) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) } }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }

  # 受注側が取引関係を結んで発注を許し、品目を登録する。品目の ID を返す
  def prepare_supplier
    login_as(supplier_admin)
    partnership = mutate!("establishPartnership", "partnership { id }", partnerCode: buyer.partner_code).dig("partnership", "id")
    mutate!("grantPermission", "partnership { id }", partnershipId: partnership, permission: "PLACE_ORDERS")
    mutate!("saveItem", "item { id }", code: "BOLT-8", name: "六角ボルト M8", unit: "本", unitPrice: "120").dig("item", "id")
  end

  def sales_orders
    query("{ supplier { salesOrders { nodes { status customer { name } lines { customerPartNumber itemName unitPrice } } } } }")
      .dig("supplier", "salesOrders", "nodes")
  end

  def purchase_order(id)
    query(<<~GRAPHQL, id:).dig("buyer", "purchaseOrder")
      query($id: ID!) { buyer { purchaseOrder(id: $id) { status lines { partNumber confirmedItemName confirmedUnitPrice } } } }
    GRAPHQL
  end

  {
    "イベントを 1 回ずつ届いた順に流す" => {},
    "同じイベントを 2 回ずつ流す" => { times: 2 },
    "新しいイベントから流す" => { newest_first: true }
  }.each do |name, delivery|
    it "#{name}と、照合待ちの受注が対応表の登録で確定し、受注は 1 件で、発注は「受注済」になる" do
      item_id = prepare_supplier

      login_as(buyer_member)
      purchase_order_id = mutate!("placePurchaseOrder", "purchaseOrder { id status }",
        supplierTenantId: supplier.id, lines: [ { partNumber: "MY-BOLT", quantity: 2 } ]).dig("purchaseOrder", "id")
      # 「発注登録」だけを流す。受注側は照合できずに照合待ちの受注を作り、「品番照合待ち」を出す
      deliver_oldest_event(times: delivery.fetch(:times, 1))

      login_as(supplier_admin)
      expect(sales_orders).to eq([ { "status" => "AWAITING_PART_MATCH", "customer" => { "name" => "組立メーカー" },
        "lines" => [ { "customerPartNumber" => "MY-BOLT", "itemName" => nil, "unitPrice" => nil } ] } ])
      mutate!("registerPartMapping", "partMapping { customerPartNumber }",
        customerTenantId: buyer.id, customerPartNumber: "MY-BOLT", itemId: item_id)
      # 発注側には「品番照合待ち」と「受注確定」が両方届く前の状態で並んでいる
      expect(enqueued_event_jobs.map { _1.arguments.fetch("arguments").first })
        .to eq(%w[Contracts::PartMatchPending Contracts::SalesOrderConfirmed])
      deliver_enqueued_events(**delivery)

      expect(sales_orders).to eq([ { "status" => "RECEIVED", "customer" => { "name" => "組立メーカー" },
        "lines" => [ { "customerPartNumber" => "MY-BOLT", "itemName" => "六角ボルト M8", "unitPrice" => "120" } ] } ])
      login_as(buyer_member)
      expect(purchase_order(purchase_order_id)).to eq("status" => "ACCEPTED",
        "lines" => [ { "partNumber" => "MY-BOLT", "confirmedItemName" => "六角ボルト M8", "confirmedUnitPrice" => "120" } ])
    end
  end
end
