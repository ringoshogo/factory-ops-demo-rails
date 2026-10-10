require "rails_helper"
require_relative "../support/events"

# 発注側の取消依頼と受注側の審査の通し。依頼で出荷が止まり、承認で発注と出荷依頼が取り消され、却下で元の状況に戻る。
# 出荷済みの受注への依頼は、審査を作らずに自動で却下される（docs/architecture/context-map.md「取消の流れ」）
RSpec.describe "取消依頼と審査", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:supplier_admin) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) } }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }

  def login_as(user)
    post "/session", params: { email: user.email, password: "password" }, as: :json
    expect(response).to have_http_status(:no_content)
  end

  def graphql(query, **variables)
    post "/graphql", params: { query:, variables: }, as: :json
    expect(response.parsed_body["errors"]).to be_nil
    response.parsed_body.fetch("data")
  end

  def mutate(name, selection, **input)
    graphql(<<~GRAPHQL, input:).fetch(name)
      mutation($input: #{name[0].upcase}#{name[1..]}Input!) { #{name}(input: $input) { #{selection} errors { code } } }
    GRAPHQL
  end

  def purchase_order
    graphql(<<~GRAPHQL, id: @purchase_order_id).dig("buyer", "purchaseOrder")
      query($id: ID!) { buyer { purchaseOrder(id: $id) { status cancellationPending cancellationRequests { reason outcome decidedAt } } } }
    GRAPHQL
  end

  def sales_order
    graphql(<<~GRAPHQL, id: @sales_order_id).dig("supplier", "salesOrder")
      query($id: ID!) {
        supplier { salesOrder(id: $id) {
          status cancellationReviewPending cancellationReviews { id requestedAt decision decidedAt }
          shipmentRequest { status instruction { plannedDate } }
        } }
      }
    GRAPHQL
  end

  # 取引関係と品目・対応表・在庫を整え、発注から受注・全量の引当・出荷指示まで進める
  before do
    login_as(supplier_admin)
    partnership_id = mutate("establishPartnership", "partnership { id }", partnerCode: buyer.partner_code).dig("partnership", "id")
    mutate("grantPermission", "partnership { id }", partnershipId: partnership_id, permission: "PLACE_ORDERS")
    item_id = mutate("saveItem", "item { id }", code: "BOLT-8", name: "六角ボルト M8", unit: "本", unitPrice: "120").dig("item", "id")
    mutate("registerPartMapping", "partMapping { id }", customerTenantId: buyer.id, customerPartNumber: "MY-BOLT", itemId: item_id)
    mutate("adjustStock", "stock { onHand }", itemId: item_id, type: "INBOUND", quantity: 10)

    login_as(buyer_member)
    @purchase_order_id = mutate("placePurchaseOrder", "purchaseOrder { id }",
      supplierTenantId: supplier.id, lines: [ { partNumber: "MY-BOLT", quantity: 4 } ]).dig("purchaseOrder", "id")
    deliver_enqueued_events

    login_as(supplier_admin)
    @sales_order_id = graphql("{ supplier { salesOrders { nodes { id } } } }").dig("supplier", "salesOrders", "nodes").sole["id"]
    mutate("allocateSalesOrder", "salesOrder { id }", salesOrderId: @sales_order_id)
    deliver_enqueued_events
    @request_id = graphql("{ supplier { shipmentRequests { nodes { id } } } }").dig("supplier", "shipmentRequests", "nodes").sole["id"]
    mutate("createShippingInstruction", "shipmentRequest { id }", shipmentRequestId: @request_id, plannedDate: "2026-10-20")
  end

  def request_cancellation
    login_as(buyer_member)
    expect(mutate("requestPurchaseOrderCancellation", "purchaseOrder { status cancellationPending }",
      purchaseOrderId: @purchase_order_id, reason: "数量の誤り"))
      .to eq("purchaseOrder" => { "status" => "ACCEPTED", "cancellationPending" => true }, "errors" => [])
    deliver_enqueued_events
    login_as(supplier_admin)
  end

  def review_id = sales_order.fetch("cancellationReviews").sole.fetch("id")

  # 操作者のテナントが書いた監査の行（docs/architecture/graphql-schema.md「監査ログ」の表）
  def audit_rows(tenant, action)
    Tenancy.with_tenant(tenant.id) do
      AuditLog.where(action:).pluck(:actor_user_id, :target_type, :target_id, :counterparty_tenant_id)
    end
  end

  it "依頼で出荷が止まり、承認すると発注が取消済み・出荷依頼が取消済になり、引当が解除される" do
    request_cancellation

    expect(sales_order).to match("status" => "ALLOCATED", "cancellationReviewPending" => true,
      "cancellationReviews" => [ { "id" => be_present, "requestedAt" => be_present, "decision" => nil, "decidedAt" => nil } ],
      "shipmentRequest" => { "status" => "ON_HOLD", "instruction" => { "plannedDate" => "2026-10-20" } })
    expect(mutate("postShipment", "shipmentRequest { status }", shipmentRequestId: @request_id, shippedOn: "2026-10-20"))
      .to eq("shipmentRequest" => nil, "errors" => [ { "code" => "CONFLICT" } ])

    approved_review_id = review_id
    expect(mutate("approveCancellationReview", "salesOrder { status cancellationReviewPending }", cancellationReviewId: approved_review_id))
      .to eq("salesOrder" => { "status" => "CANCELLED", "cancellationReviewPending" => false }, "errors" => [])
    deliver_enqueued_events
    expect(audit_rows(buyer, "purchase_order.request_cancellation"))
      .to eq([ [ buyer_member.id, "PurchaseOrder", @purchase_order_id, supplier.id ] ])
    expect(audit_rows(supplier, "cancellation_review.approve"))
      .to eq([ [ supplier_admin.id, "CancellationReview", approved_review_id, buyer.id ] ])

    expect(sales_order).to include("cancellationReviews" => [ include("decision" => "APPROVED", "decidedAt" => be_present) ],
      "shipmentRequest" => { "status" => "CANCELLED", "instruction" => nil })
    expect(graphql("{ supplier { stocks { nodes { onHand allocated } } } }").dig("supplier", "stocks", "nodes"))
      .to eq([ { "onHand" => 10, "allocated" => 0 } ])

    login_as(buyer_member)
    expect(purchase_order).to match("status" => "CANCELLED", "cancellationPending" => false,
      "cancellationRequests" => [ { "reason" => "数量の誤り", "outcome" => "APPROVED", "decidedAt" => be_present } ])
  end

  it "依頼を却下すると、発注は依頼の前の状況に戻り、出荷停止が解除されて計上できる" do
    request_cancellation

    rejected_review_id = review_id
    expect(mutate("rejectCancellationReview", "salesOrder { status cancellationReviewPending }", cancellationReviewId: rejected_review_id))
      .to eq("salesOrder" => { "status" => "ALLOCATED", "cancellationReviewPending" => false }, "errors" => [])
    expect(audit_rows(supplier, "cancellation_review.reject"))
      .to eq([ [ supplier_admin.id, "CancellationReview", rejected_review_id, buyer.id ] ])
    expect(mutate("approveCancellationReview", "salesOrder { status }", cancellationReviewId: review_id))
      .to eq("salesOrder" => nil, "errors" => [ { "code" => "CONFLICT" } ])
    deliver_enqueued_events

    expect(sales_order.fetch("shipmentRequest")).to eq("status" => "INSTRUCTED", "instruction" => { "plannedDate" => "2026-10-20" })
    expect(mutate("postShipment", "shipmentRequest { status }", shipmentRequestId: @request_id, shippedOn: "2026-10-20"))
      .to eq("shipmentRequest" => { "status" => "SHIPPED" }, "errors" => [])

    login_as(buyer_member)
    expect(purchase_order).to match("status" => "ACCEPTED", "cancellationPending" => false,
      "cancellationRequests" => [ { "reason" => "数量の誤り", "outcome" => "REJECTED", "decidedAt" => be_present } ])
  end

  it "出荷済みの受注への依頼は、審査を作らずに自動で却下され、発注は入荷予定のまま" do
    mutate("postShipment", "shipmentRequest { status }", shipmentRequestId: @request_id, shippedOn: "2026-10-20")
    deliver_enqueued_events

    login_as(buyer_member)
    expect(mutate("requestPurchaseOrderCancellation", "purchaseOrder { status cancellationPending }",
      purchaseOrderId: @purchase_order_id, reason: "数量の誤り"))
      .to eq("purchaseOrder" => { "status" => "INBOUND", "cancellationPending" => true }, "errors" => [])
    deliver_enqueued_events

    expect(purchase_order).to match("status" => "INBOUND", "cancellationPending" => false,
      "cancellationRequests" => [ { "reason" => "数量の誤り", "outcome" => "REJECTED", "decidedAt" => be_present } ])
    login_as(supplier_admin)
    expect(sales_order).to include("status" => "SHIPPED", "cancellationReviewPending" => false, "cancellationReviews" => [])
  end

  it "回答待ちの依頼がある発注への依頼と、見えない審査は、ユーザーエラーに写る" do
    request_cancellation

    expect(mutate("approveCancellationReview", "salesOrder { id }", cancellationReviewId: SecureRandom.uuid))
      .to eq("salesOrder" => nil, "errors" => [ { "code" => "NOT_FOUND" } ])
    login_as(buyer_member)
    expect(mutate("requestPurchaseOrderCancellation", "purchaseOrder { id }", purchaseOrderId: @purchase_order_id, reason: "再依頼"))
      .to eq("purchaseOrder" => nil, "errors" => [ { "code" => "CONFLICT" } ])
  end
end
