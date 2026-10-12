require "rails_helper"

# 同じ出荷依頼の postShipment を、2 つの接続から GraphQL の入口を通して同時に送ると、成立した 1 件だけが監査の行を持つ。
# 監査の行は mutation の基底クラスが要求のトランザクションの中で書く（docs/architecture/graphql-schema.md「監査ログ」）。
# 監査の行とテナントとユーザーは後始末で消せないので残る（docs/guides/testing.md「競合テスト」）
RSpec.describe "出荷の計上の競合と監査ログ" do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:user) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:actor) { Partnerships::Actor.new(user_id: user.id, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:item_id) { SecureRandom.uuid }
  # 在庫を 10 入れ、出荷依頼の明細 1 つを全量で引き当て、有効な出荷指示を作っておく
  let!(:request) do
    Tenancy.with_tenant(supplier.id) do
      Inventory::Adjustment.adjust(actor, item_id:, type: "inbound", quantity: 10)
      FactoryBot.create(:shipping_instruction).shipment_request.tap do |request|
        line = FactoryBot.create(:shipment_request_line, shipment_request: request, item_id:, quantity: 3)
        Inventory::Allocation.allocate(actor, [ { sales_order_line_id: line.sales_order_line_id, item_id:, quantity: 3 } ])
      end
    end
  end

  after do
    delete_owned_rows([ supplier.id, request.buyer_tenant_id ], %w[
      shipment_lines shipments shipping_instructions shipment_request_lines shipment_requests
      stock_movements allocations stocks
    ])
  end

  # スレッドごとに、ログインした別のセッションを持つ
  def logged_in_session
    ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.post "/session", params: { email: user.email, password: "password" }, as: :json
      expect(session.response).to have_http_status(:no_content)
    end
  end

  # postShipment を送り、[ユーザーエラーのコード, 要求 ID] を返す
  def post_shipment(session)
    session.post "/graphql", as: :json, params: {
      query: "mutation($input: PostShipmentInput!) { postShipment(input: $input) { errors { code } } }",
      variables: { input: { shipmentRequestId: request.id, shippedOn: "2026-10-10" } }
    }
    [ session.response.parsed_body.dig("data", "postShipment", "errors").map { _1["code"] }, session.response.headers["X-Request-Id"] ]
  end

  def audit_rows
    Tenancy.with_tenant(supplier.id) do
      ActiveRecord::Base.lease_connection.select_rows(<<~SQL)
        SELECT action, request_id FROM audit_logs WHERE action = 'shipment.post' ORDER BY id
      SQL
    end
  end

  it "後の計上は先の計上のコミットを待って CONFLICT になり、監査の行は先の要求の 1 行だけになる" do
    first, second = Array.new(2) { logged_in_session }

    posted, release, poster = hold_open(supplier.id) { post_shipment(first) }
    expect(posted.first).to eq([])

    waiter = in_thread(supplier.id) { post_shipment(second) }
    expect(blocked_on_lock?(waiter, by: poster)).to be(true)

    expect(commit(release, poster)).to eq(posted)
    conflicted = finish(waiter)
    expect(conflicted.first).to eq([ "CONFLICT" ])
    expect(audit_rows).to eq([ [ "shipment.post", posted.last ] ])
  end
end
