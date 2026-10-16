require "rails_helper"
require_relative "../support/events"

# テナントをまたぐ一連の処理を、1 つの相関 ID でログから引ける（docs/guides/config.md「ログ」、
# docs/architecture/data-model.md「イベントの受け口と冪等キー」）。発注側の発注の要求 → 「発注登録」 → 受注側の購買のイベントの受け手 →
# 「受注確定」 → 購買の受け手、の全ログ行が、発注の要求の request_id を相関 ID に持つ。
# 受け手の行の因果 ID は、届いたイベントの event_id である
RSpec.describe "相関 ID と因果 ID", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }
  let(:io) { StringIO.new }
  let(:log) { Platform::JsonLogSubscriber.new(io) }

  before do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders])
      item = FactoryBot.create(:item, code: "BOLT-8")
      FactoryBot.create(:customer_part_mapping, customer_tenant_id: buyer.id, customer_part_number: "MY-BOLT", item:)
    end
    post "/session", params: { email: buyer_member.email, password: "password" }, as: :json
    expect(response).to have_http_status(:no_content)
  end

  after { Rails.event.unsubscribe(log) }

  def place_purchase_order
    post "/graphql", as: :json, params: {
      query: <<~GRAPHQL,
        mutation Place($input: PlacePurchaseOrderInput!) { placePurchaseOrder(input: $input) { errors { code } } }
      GRAPHQL
      operationName: "Place",
      variables: { input: { supplierTenantId: supplier.id, lines: [ { partNumber: "MY-BOLT", quantity: 1 } ] } }
    }
    expect(response.parsed_body.dig("data", "placePurchaseOrder", "errors")).to eq([])
    response.headers.fetch("X-Request-Id")
  end

  def lines = io.string.lines.map { JSON.parse(_1) }

  # Contracts.publish が登録したイベントのジョブの付帯情報を、イベントの名前で引く
  def metadata_of(event_name)
    SolidQueue::Job.where(class_name: "Contracts::EventJob").map { _1.arguments.fetch("app_metadata") }
      .select { _1.fetch("event_name") == event_name }.sole
  end

  it "発注の要求から購買の受け手までの全ログ行が、要求の request_id を相関 ID に持ち、受け手の因果 ID は届いたイベントの ID である" do
    Rails.event.subscribe(log)
    request_id = place_purchase_order
    deliver_enqueued_events

    expect(lines.map { _1.dig("context", "correlation_id") }).to all(eq(request_id))
    expect(lines.map { _1["name"] }).to include("action_controller.request_started", "action_controller.request_completed",
      "graphql.operation_completed", "active_job.started", "active_job.completed", "contracts.event_handled")

    placed = metadata_of("Contracts::PurchaseOrderPlaced")
    confirmed = metadata_of("Contracts::SalesOrderConfirmed")
    expect(placed).to include("correlation_id" => request_id, "causation_id" => nil,
      "source_tenant_id" => buyer.id, "tenant_id" => supplier.id)
    expect(confirmed).to include("correlation_id" => request_id, "causation_id" => placed.fetch("event_id"),
      "source_tenant_id" => supplier.id, "tenant_id" => buyer.id)

    handled = lines.select { _1["name"] == "contracts.event_handled" }
    expect(handled.map { [ _1.dig("payload", "event_name"), _1.dig("payload", "receiver"), _1["context"] ] }).to include(
      [ "Contracts::PurchaseOrderPlaced", "Sales::PurchaseOrderTranslator",
        include("tenant_id" => supplier.id, "event_id" => placed.fetch("event_id"), "causation_id" => placed.fetch("event_id")) ],
      [ "Contracts::SalesOrderConfirmed", "Purchasing::SupplierEventReceiver",
        include("tenant_id" => buyer.id, "event_id" => confirmed.fetch("event_id"), "causation_id" => confirmed.fetch("event_id")) ]
    )
    expect(handled.map { _1.dig("payload", "delivery_lag_ms") }).to all(be_a(Integer).and(be >= 0))
    expect(lines.select { _1["name"].start_with?("active_job.started") }.map { _1.dig("context", "event_id") })
      .to include(placed.fetch("event_id"), confirmed.fetch("event_id"))
  end

  it "相関 ID の無い文脈で発行したイベントは、そのイベントから一連の処理が始まり、自分の ID を相関 ID にする" do
    Tenancy.with_tenant(supplier.id) do
      Contracts.publish(Contracts::SalesOrderConfirmed.new(purchase_order_id: SecureRandom.uuid, buyer_tenant_id: buyer.id,
        supplier_tenant_id: supplier.id, lines: [], occurred_at: Time.current.iso8601(6)))
    end

    metadata = metadata_of("Contracts::SalesOrderConfirmed")
    expect(metadata).to include("correlation_id" => metadata.fetch("event_id"), "causation_id" => nil)
  end

  it "要求の開始の行には request_id と相関 ID が付き、テナントとユーザーと操作名はスキーマの実行の中の行から付く" do
    Rails.event.subscribe(log)
    request_id = place_purchase_order

    contexts = lines.to_h { [ _1["name"], _1["context"] ] }
    expect(contexts.fetch("action_controller.request_started")).to eq("request_id" => request_id, "correlation_id" => request_id)
    # スキーマの実行の中で出るイベント（ジョブの登録と操作の終わり）にも、実行の前に設定した文脈が付く
    expect(contexts.values_at("active_job.enqueued", "graphql.operation_completed", "action_controller.request_completed"))
      .to all(eq("request_id" => request_id, "correlation_id" => request_id,
        "tenant_id" => buyer.id, "user_id" => buyer_member.id, "graphql_operation" => "Place"))
  end
end
