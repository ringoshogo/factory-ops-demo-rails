require_relative "tenant_helpers"

# 行列テストの世界（docs/implementation-plan.md M6）。ペルソナごとにテナントと admin のユーザーを作り、
# テナントの表ごとに、どのペルソナも自社の行を factory で 1 件以上持つようにする
class MatrixWorld
  include TenantHelpers

  # M8 で granted_buyer・ungranted_buyer・revoked_buyer を足す
  PERSONAS = %i[supplier stranger].freeze

  attr_reader :tenants, :users

  def self.tenant_tables
    ActiveRecord::Base.lease_connection.select_values(<<~SQL)
      SELECT table_name FROM information_schema.columns
      WHERE table_schema = 'public' AND column_name = 'owner_tenant_id'
      ORDER BY table_name
    SQL
  end

  # 表の行を作る factory。名前は表の単数形にする
  def self.factory_name(table) = table.singularize.to_sym

  def initialize
    @tenants = PERSONAS.index_with { |persona| create_tenant(persona.to_s) }
    @users = PERSONAS.index_with { |persona| as(persona) { FactoryBot.create(:user, :admin) } }
    @rows = self.class.tenant_tables.index_with do |table|
      PERSONAS.index_with { |persona| as(persona) { FactoryBot.create(self.class.factory_name(table)) } }
    end
  end

  def as(persona, &)
    Tenancy.with_tenant(tenants.fetch(persona), &)
  end

  # ペルソナがその表に所有する行の 1 つ
  def row(table, persona) = @rows.fetch(table).fetch(persona)

  def persona_of(tenant_id) = tenants.key(tenant_id) || tenant_id
end
