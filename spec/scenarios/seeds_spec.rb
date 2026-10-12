require "rails_helper"
require_relative "../support/scenarios"

# シードの世界（README.md「開発環境」）。デモを開いた人が、両社の admin と member のどちらでログインしても、受注側の画面と、
# 発注側が相手のデータを読む経路を見られる。失効済みの発注側は、相手を読む経路が閉じ、自社の発注と受領請求書だけが残る
# （docs/architecture/graphql-schema.md「発注側の視点」、docs/architecture/context-map.md「取引関係の失効」）
RSpec.describe "シード", type: :request do
  let!(:world) { DemoWorld.build(namespace: "", variant: :seed) }
  let(:supplier_id) { world.tenant_ids.fetch(:supplier) }

  def log_in(persona)
    account = world.accounts.find { _1.persona == persona }
    post "/session", params: { email: account.email, password: account.password }, as: :json
    expect(response).to have_http_status(:no_content)
  end

  def nodes(text, *path, **variables) = query(text, **variables).dig(*path, "nodes")

  # 発注側から見た 3 経路。経路 1 は受注側のカタログ、経路 2 は取引先の一覧、経路 3 は自社の発注に連結した出荷
  def partner_reads
    { suppliers: query("{ buyer { suppliers { supplier { name } } } }").dig("buyer", "suppliers"),
      catalog: query("query($id: ID!) { buyer { supplier(supplierTenantId: $id) { catalog { nodes { code } } } } }", id: supplier_id)
        .dig("buyer", "supplier", "catalog", "nodes"),
      shipments: nodes("{ buyer { purchaseOrders(first: 100) { nodes { supplierShipments { shippedOn } } } } }", "buyer", "purchaseOrders")
        .flat_map { _1.fetch("supplierShipments") } }
  end

  %w[admin member].each do |role|
    it "受注側の #{role} で supplier.dashboard を読むと、状況ごとの件数が空でない" do
      log_in("supplier_#{role}")

      counts = query("{ supplier { dashboard { salesOrderCounts { status count } } } }").dig("supplier", "dashboard", "salesOrderCounts")

      expect(counts.select { _1["count"].positive? }.map { _1["status"] })
        .to match_array(%w[CANCELLED INSPECTED SHIPPED AWAITING_PART_MATCH ALLOCATED PARTIALLY_ALLOCATED RECEIVED])
    end

    it "受注側の #{role} は、受注・請求書・取り込みの一覧とダッシュボードの集計を読める" do
      log_in("supplier_#{role}")

      dashboard = query("{ supplier { dashboard { stocksBelowSafetyStock { item { code } } shipmentRequestsDueSoon { id } unbilledTotal } } }")
        .dig("supplier", "dashboard")
      expect(dashboard.fetch("stocksBelowSafetyStock").map { _1.dig("item", "code") }).to include("ITM-006", "ITM-016")
      expect(dashboard.fetch("shipmentRequestsDueSoon")).not_to be_empty
      expect(dashboard.fetch("unbilledTotal").to_i).to be_positive
      expect(nodes("{ supplier { salesOrders(first: 100) { nodes { id } } } }", "supplier", "salesOrders").size).to eq(14)
      expect(nodes("{ supplier { invoices { nodes { state } } } }", "supplier", "invoices").map { _1["state"] })
        .to match_array(%w[ISSUED DRAFT ISSUED])
      expect(nodes("{ supplier { imports { nodes { status } } } }", "supplier", "imports")).to eq([ { "status" => "PARTIALLY_FAILED" } ])
    end

    it "全権限の付与がある発注側の #{role} は、取引先とそのカタログと、自社の発注に連結した出荷を読める" do
      log_in("granted_buyer_#{role}")

      reads = partner_reads
      expect(reads[:suppliers]).to eq([ { "supplier" => { "name" => "青嵐精機工業" } } ])
      expect(reads[:catalog].map { _1["code"] }).to include("ITM-001", "ITM-019", "ITM-021")
      expect(reads[:catalog].map { _1["code"] }).not_to include("ITM-020")
      expect(reads[:shipments]).not_to be_empty
    end

    it "失効済みの発注側の #{role} は、取引先・カタログ・出荷が空になり、自社の発注と受領請求書は読める" do
      log_in("revoked_buyer_#{role}")

      expect(partner_reads).to eq(suppliers: [], catalog: nil, shipments: [])
      expect(nodes("{ buyer { purchaseOrders { nodes { status } } } }", "buyer", "purchaseOrders").map { _1["status"] })
        .to match_array(%w[INSPECTED INBOUND])
      expect(nodes("{ buyer { receivedInvoices { nodes { invoiceNumber } } } }", "buyer", "receivedInvoices").size).to eq(1)
    end
  end

  it "業務の日付はシードを流した日で、入力で渡す日付は今日からの差になる" do
    log_in("supplier_admin")

    orders = nodes("{ supplier { salesOrders(first: 100) { nodes { orderDate dueDate } } } }", "supplier", "salesOrders")
    expect(orders.map { _1["orderDate"] }.uniq).to eq([ Date.current.iso8601 ])
    expect(orders.map { Date.iso8601(_1["dueDate"]) - Date.current }).to all(be_between(2, 12))
  end
end
