require "rails_helper"
require_relative "../support/events"

# 相手テナントに効果が及ぶ書き込みは、業務の行と同じトランザクションで監査ログに 1 行残り、業務の行と一緒に戻る
# （docs/architecture/graphql-schema.md「監査ログ」「1 回のリクエストがたどる道」）
RSpec.describe "監査ログの記録", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }
  let(:supplier_member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let!(:partnership) do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders]) }
  end
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item) } }

  before do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:customer_part_mapping, customer_tenant_id: buyer.id, customer_part_number: "MY-BOLT", item:)
      FactoryBot.create(:stock, item_id: item.id, on_hand: 100)
    end
  end

  PLACE = "placePurchaseOrder(input: %s) { purchaseOrder { id } errors { code } }".freeze

  def place_input(supplier_tenant_id = supplier.id) = { supplierTenantId: supplier_tenant_id, lines: [ { partNumber: "MY-BOLT", quantity: 1 } ] }

  def place(supplier_tenant_id = supplier.id)
    graphql_body("mutation($input: PlacePurchaseOrderInput!) { #{format(PLACE, '$input')} }", input: place_input(supplier_tenant_id))
      .dig("data", "placePurchaseOrder")
  end

  def audit_rows(tenant)
    Tenancy.with_tenant(tenant.id) do
      AuditLog.order(:id).map do |row|
        row.attributes.slice("actor_type", "actor_user_id", "action", "target_type", "target_id", "counterparty_tenant_id",
          "request_id", "correlation_id", "causation_id").compact
      end
    end
  end

  def purchase_order_ids = Tenancy.with_tenant(buyer.id) { ActiveRecord::Base.lease_connection.select_values("SELECT id FROM purchase_orders") }

  def event_job_count = SolidQueue::Job.where(class_name: "Contracts::EventJob").count

  describe "1. mutation の成功と失敗" do
    it "placePurchaseOrder の成功で、操作者・対象・相手・要求 ID の付いた行が 1 行できる" do
      login_as(buyer_member)
      placed = place

      expect(audit_rows(buyer)).to eq([ {
        "actor_type" => "user", "actor_user_id" => buyer_member.id, "action" => "purchase_order.place",
        "target_type" => "PurchaseOrder", "target_id" => placed.dig("purchaseOrder", "id"), "counterparty_tenant_id" => supplier.id,
        "request_id" => response.headers["X-Request-Id"], "correlation_id" => response.headers["X-Request-Id"]
      } ])
    end

    it "NOT_PERMITTED では行ができない" do
      login_as(buyer_member)

      expect(place(FactoryBot.create(:tenant).id)["errors"]).to eq([ { "code" => "NOT_PERMITTED" } ])
      expect(audit_rows(buyer)).to eq([])
    end
  end

  # graphql-schema.md「監査ログ」の表の、mutation ごとの対象と相手
  it "audit の mutation は、宣言した対象と相手で 1 行ずつ書く" do
    supplier_admin = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) }
    newcomer = FactoryBot.create(:tenant)
    request = Tenancy.with_tenant(supplier.id) do
      allocation = FactoryBot.create(:allocation)
      FactoryBot.create(:shipping_instruction, shipment_request: FactoryBot.create(:shipment_request, buyer_tenant_id: buyer.id))
        .shipment_request.tap do |request|
          FactoryBot.create(:shipment_request_line, shipment_request: request, sales_order_line_id: allocation.sales_order_line_id,
            item_id: allocation.item_id, quantity: allocation.quantity)
        end
    end
    login_as(supplier_admin)
    run = lambda do |name, selection, input|
      body = graphql_body("mutation($input: #{name.camelize}Input!) { #{name}(input: $input) { #{selection} errors { code } } }", input:)
      expect(body.dig("data", name, "errors")).to eq([]), name
      body.dig("data", name)
    end

    established = run.("establishPartnership", "partnership { id }", { partnerCode: newcomer.partner_code })
    run.("grantPermission", "partnership { id }", { partnershipId: partnership.id, permission: "VIEW_CATALOG" })
    run.("withdrawPermission", "partnership { id }", { partnershipId: partnership.id, permission: "PLACE_ORDERS" })
    saved = run.("saveItem", "item { id }", { code: "NEW-1", name: "新しい品目", unit: "個", unitPrice: 100 })
    run.("setItemPublished", "item { id }", { itemId: item.id, published: true })
    mapped = run.("registerPartMapping", "partMapping { id }", { customerTenantId: buyer.id, customerPartNumber: "NEW-PART", itemId: item.id })
    shipped = run.("postShipment", "shipmentRequest { shipment { id } }", { shipmentRequestId: request.id, shippedOn: "2026-10-10" })
    run.("revokePartnership", "partnership { id }", { partnershipId: partnership.id })

    expect(audit_rows(supplier).map { _1.values_at("action", "target_type", "target_id", "counterparty_tenant_id", "actor_user_id") }).to eq([
      [ "partnership.establish", "Partnership", established.dig("partnership", "id"), newcomer.id ],
      [ "partnership.grant_permission", "Partnership", partnership.id, buyer.id ],
      [ "partnership.withdraw_permission", "Partnership", partnership.id, buyer.id ],
      [ "item.save", "Item", saved.dig("item", "id"), nil ],
      [ "item.set_published", "Item", item.id, nil ],
      [ "part_mapping.register", "PartMapping", mapped.dig("partMapping", "id"), buyer.id ],
      [ "shipment.post", "Shipment", shipped.dig("shipmentRequest", "shipment", "id"), buyer.id ],
      [ "partnership.revoke", "Partnership", partnership.id, buyer.id ]
    ].map { _1 + [ supplier_admin.id ] })
  end

  describe "1 つの要求の 2 つの mutation" do
    it "2. 先が成功し後がユーザーエラーなら、先の業務の行・監査の行・イベントのジョブが残り、後の分は何も残らない" do
      login_as(buyer_member)
      body = graphql_body(<<~GRAPHQL, a: place_input, b: place_input(FactoryBot.create(:tenant).id))
        mutation($a: PlacePurchaseOrderInput!, $b: PlacePurchaseOrderInput!) {
          first: #{format(PLACE, '$a')}
          second: #{format(PLACE, '$b')}
        }
      GRAPHQL

      expect(body.dig("data", "second", "errors")).to eq([ { "code" => "NOT_PERMITTED" } ])
      expect(purchase_order_ids).to eq([ body.dig("data", "first", "purchaseOrder", "id") ])
      expect(audit_rows(buyer).map { _1["target_id"] }).to eq(purchase_order_ids)
      expect(event_job_count).to eq(1)
    end

    it "3. 先が成功し後がトップレベルのエラー（FORBIDDEN）なら、どれも残らない" do
      login_as(buyer_member)
      body = graphql_body(<<~GRAPHQL, a: place_input)
        mutation($a: PlacePurchaseOrderInput!) {
          first: #{format(PLACE, '$a')}
          second: establishPartnership(input: { partnerCode: "anything" }) { errors { code } }
        }
      GRAPHQL

      expect(body["errors"].map { _1.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
      expect(purchase_order_ids).to eq([])
      expect(audit_rows(buyer)).to eq([])
      expect(event_job_count).to eq(0)
    end
  end

  it "4. 監査の行の INSERT が失敗すると、業務の行もイベントのジョブも残らない" do
    # 必須の列を空にして、DB に INSERT を拒ませる
    allow(AuditLog).to receive(:insert!).and_wrap_original { |original, attributes, **| original.call(attributes.merge(action: nil)) }
    login_as(buyer_member)

    expect { place }.to raise_error(ActiveRecord::NotNullViolation, /action/)
    expect(purchase_order_ids).to eq([])
    expect(event_job_count).to eq(0)
  end

  # 要求の外でスキーマを流すと、相関 ID の文脈が無い（OI-42）
  it "相関 ID の無い文脈で audit の mutation を流すと、監査の行の INSERT が失敗し、業務の行もイベントのジョブも残らない" do
    actor = Tenancy.with_tenant(buyer.id) { Partnerships::Authentication.actor(buyer_member.id, session_version: buyer_member.session_version) }
    Rails.event.clear_context

    expect {
      Tenancy.with_tenant(buyer.id) do
        Current.set(actor:) do
          FactoryOpsSchema.execute("mutation($input: PlacePurchaseOrderInput!) { #{format(PLACE, '$input')} }",
            variables: { "input" => place_input }, context: { current_user: actor })
        end
      end
    }.to raise_error(ActiveRecord::NotNullViolation, /correlation_id/)
    expect([ purchase_order_ids, audit_rows(buyer), event_job_count ]).to eq([ [], [], 0 ])
  end

  describe "イベントの受信" do
    def sales_order_count = Tenancy.with_tenant(supplier.id) { ActiveRecord::Base.lease_connection.select_value("SELECT count(*) FROM sales_orders") }

    def received(tenant) = audit_rows(tenant).select { _1["action"] == "event.received" }

    # 登録済みのイベントのうち、最も古い 1 件だけを受け手まで流す。受け手が失敗すると、ジョブは終わらずに残る
    def deliver_oldest_event
      job = enqueued_event_jobs.first
      BulletDetection.wrap { ActiveJob::Base.execute(job.arguments) }
      job.finished!
    end

    it "5. 受け手が例外を投げると、受信の行も受け手の書き込みも残らない。再実行で成功すると 1 行になる" do
      login_as(buyer_member)
      place
      allow(Sales::PurchaseOrderTranslator).to receive(:handle).and_wrap_original do |original, event|
        original.call(event)
        raise "受け手の失敗"
      end

      expect { deliver_oldest_event }.to raise_error("受け手の失敗")
      expect([ sales_order_count, received(supplier) ]).to eq([ 0, [] ])

      allow(Sales::PurchaseOrderTranslator).to receive(:handle).and_call_original
      deliver_oldest_event
      expect([ sales_order_count, received(supplier).size ]).to eq([ 1, 1 ])
    end

    it "6. 受注側に「発注登録」、発注側に「受注確定」の受信の行ができ、2 回流しても増えない。同じテナントの中の「出荷可能」では行ができない" do
      login_as(buyer_member)
      place_request_id = (place && response.headers["X-Request-Id"])
      jobs = SolidQueue::Job.where(class_name: "Contracts::EventJob")
      event_ids = -> { jobs.order(:id).map { _1.arguments.dig("app_metadata", "event_id") } }
      deliver_enqueued_events(times: 2)
      placed_event, confirmed_event = event_ids.call

      expect(received(supplier)).to eq([ {
        "actor_type" => "system", "action" => "event.received", "target_type" => "PurchaseOrderPlaced", "target_id" => placed_event,
        "counterparty_tenant_id" => buyer.id, "correlation_id" => place_request_id, "causation_id" => placed_event
      } ])
      expect(received(buyer)).to eq([ {
        "actor_type" => "system", "action" => "event.received", "target_type" => "SalesOrderConfirmed", "target_id" => confirmed_event,
        "counterparty_tenant_id" => supplier.id, "correlation_id" => place_request_id, "causation_id" => confirmed_event
      } ])

      login_as(supplier_member)
      sales_order_id = graphql_body("{ supplier { salesOrders { nodes { id } } } }").dig("data", "supplier", "salesOrders", "nodes", 0, "id")
      allocated = graphql_body("mutation($input: AllocateSalesOrderInput!) { allocateSalesOrder(input: $input) { errors { code } } }",
        input: { salesOrderId: sales_order_id })
      expect(allocated.dig("data", "allocateSalesOrder", "errors")).to eq([])
      expect(jobs.order(:id).last.arguments.dig("app_metadata", "event_name")).to eq("Contracts::SalesOrderReadyForShipment")
      deliver_enqueued_events

      expect(audit_rows(supplier).map { _1["action"] }).to eq([ "event.received" ])
    end

    it "7. 発注側の mutation の行と、受注側の受信の行が、同じ相関 ID を持つ" do
      login_as(buyer_member)
      place
      deliver_enqueued_events

      correlation_ids = [ audit_rows(buyer).first, received(supplier).first ].map { _1["correlation_id"] }
      expect(correlation_ids).to eq([ response.headers["X-Request-Id"] ] * 2)
    end
  end

  describe "viewer.auditLogs" do
    let(:buyer_admin) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user, :admin, name: "発注の管理者") } }

    def audit_logs(filter = {})
      graphql_body(<<~GRAPHQL, filter:)
        query($filter: AuditLogFilter) {
          viewer { auditLogs(filter: $filter) { nodes { action actorName targetType targetId counterparty { name } correlationId } } }
        }
      GRAPHQL
    end

    it "admin には、自社の行だけを新しいものから、操作者と相手の名前を付けて返す" do
      login_as(buyer_admin)
      placed = place
      place_request_id = response.headers["X-Request-Id"]
      deliver_enqueued_events
      confirmed_event = SolidQueue::Job.where(class_name: "Contracts::EventJob").order(:id).last.arguments.dig("app_metadata", "event_id")

      expect(audit_logs.dig("data", "viewer", "auditLogs", "nodes")).to eq([
        { "action" => "event.received", "actorName" => nil, "targetType" => "SalesOrderConfirmed", "targetId" => confirmed_event,
          "counterparty" => { "name" => supplier.name }, "correlationId" => place_request_id },
        { "action" => "purchase_order.place", "actorName" => "発注の管理者", "targetType" => "PurchaseOrder",
          "targetId" => placed.dig("purchaseOrder", "id"), "counterparty" => { "name" => supplier.name }, "correlationId" => place_request_id }
      ])
    end

    it "action・相関 ID・時刻の範囲で絞る" do
      login_as(buyer_admin)
      place
      first_request_id = response.headers["X-Request-Id"]
      place
      deliver_enqueued_events
      actions = ->(filter) { audit_logs(filter).dig("data", "viewer", "auditLogs", "nodes").map { _1.values_at("action", "correlationId") } }

      expect(actions.(action: "purchase_order.place").map(&:first)).to eq(%w[purchase_order.place] * 2)
      expect(actions.(correlationId: first_request_id))
        .to contain_exactly([ "purchase_order.place", first_request_id ], [ "event.received", first_request_id ])
      expect(actions.(occurredFrom: 1.minute.from_now.iso8601)).to eq([])
      expect(actions.(occurredTo: 1.minute.ago.iso8601)).to eq([])
      expect(actions.(occurredFrom: 1.minute.ago.iso8601, occurredTo: 1.minute.from_now.iso8601).size).to eq(4)
    end

    it "member には FORBIDDEN を返す" do
      login_as(buyer_member)

      expect(audit_logs["errors"].map { _1.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
    end
  end
end
