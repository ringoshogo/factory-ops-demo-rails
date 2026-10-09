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
