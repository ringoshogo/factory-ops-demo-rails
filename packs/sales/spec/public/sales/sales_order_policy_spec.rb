require "rails_helper"
require_relative "../../../../../spec/support/owner_connection"

# 受注の scope の自社テナントの条件は、RLS が無くても単独で他社の受注を除く（docs/architecture/graphql-schema.md「認可」）。
# RLS も同じ行を閉じるので、アプリのロールで読むと条件を落としても気付けない。scope の SQL を、BYPASSRLS を持つ
# 所有ロールの接続で読んで確かめる。所有ロールの接続は別のセッションなので、例ごとのトランザクションを使わず、
# 作った行は例の後で所有ロールで消す
RSpec.describe Sales::SalesOrderPolicy do
  self.use_transactional_tests = false

  let!(:tenants) { FactoryBot.create_list(:tenant, 2) }
  let!(:orders) { tenants.map { |tenant| Tenancy.with_tenant(tenant.id) { FactoryBot.create(:sales_order) } } }

  after do
    connection = OwnerConnection.lease_connection
    ids = [ *tenants.map(&:id), *orders.map(&:customer_tenant_id) ].map { connection.quote(_1) }.join(", ")
    connection.execute("DELETE FROM sales_orders WHERE owner_tenant_id IN (#{ids})")
    connection.execute("DELETE FROM tenants WHERE id IN (#{ids})")
  end

  def actor_of(tenant)
    Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "")
  end

  def ids_without_rls(sql)
    OwnerConnection.lease_connection.select_values(sql) & orders.map(&:id)
  end

  it "RLS の掛からない接続で読んでも、scope は自社の受注だけを返す" do
    sql = Tenancy.with_tenant(tenants[0].id) { Sales::Scope.sales_orders(actor_of(tenants[0]), :own).select(:id).to_sql }

    expect(ids_without_rls("SELECT id FROM sales_orders")).to match_array(orders.map(&:id))
    expect(ids_without_rls(sql)).to eq([ orders[0].id ])
  end
end

# 受注の操作の規則。受注側の取消と取消の審査の承認・却下は、取引を取り消す操作なので自社の admin に限り、
# 引当は役割を問わない（docs/architecture/context-map.md「自社の中の役割」、docs/architecture/graphql-schema.md「役割による制限」）
RSpec.describe Sales::SalesOrderPolicy, "の規則" do
  let(:tenant_id) { SecureRandom.uuid }
  # 受注側の取消と引当は受注に対して、審査の承認・却下は審査に対して評価する
  let(:targets) do
    order = Sales::SalesOrderValue.new(id: SecureRandom.uuid, owner_tenant_id: tenant_id, order_no: "SO-000001",
      customer_tenant_id: SecureRandom.uuid, order_date: Date.current, due_date: nil, status: :confirmed, cancellation_review_pending: false)
    review = Sales::CancellationReviewValue.new(id: SecureRandom.uuid, owner_tenant_id: tenant_id, sales_order_id: order.id,
      requested_at: Time.current, decision: nil, decided_at: nil)
    { cancel?: order, review?: review, allocate?: order }
  end

  def actor(role) = Partnerships::Actor.new(user_id: SecureRandom.uuid, tenant_id:, name: "", email: "", role:, partner_code: "")

  def allowed?(rule, role, record) = described_class.new(record, user: actor(role)).apply(rule)

  %i[cancel? review?].each do |rule|
    it "#{rule} は自社の対象について、admin には真、member には偽を返す" do
      expect(allowed?(rule, "admin", targets.fetch(rule))).to be(true)
      expect(allowed?(rule, "member", targets.fetch(rule))).to be(false)
    end

    it "#{rule} は admin でも、他社の対象には偽を返す" do
      expect(allowed?(rule, "admin", targets.fetch(rule).with(owner_tenant_id: SecureRandom.uuid))).to be(false)
    end
  end

  it "引当は、自社の受注なら member にも真を返す" do
    expect(allowed?(:allocate?, "member", targets.fetch(:allocate?))).to be(true)
  end
end
