require_relative "tenant_helpers"

# 行列テストの世界（docs/implementation-plan.md M6）。ペルソナごとにテナントと admin のユーザーを作り、
# テナントの表ごとに、どのペルソナも自社の行を factory で 1 件以上持つようにする。
# そのうえで、supplier が受注側になる取引関係を 3 つ結び、supplier の公開品目を 1 件足す
# （表ごとの行は factory の既定のままなので、品目は公開しない）
class MatrixWorld
  include TenantHelpers

  PERSONAS = %i[supplier granted_buyer ungranted_buyer revoked_buyer stranger].freeze

  ALL_PERMISSIONS = %w[view_catalog place_orders view_shipments].freeze

  # supplier との取引関係。revoked_buyer は全権限の付与を持ったまま失効させ、付与があっても失効で閉じることを確かめる
  PARTNERSHIPS = {
    granted_buyer: { permissions: ALL_PERMISSIONS },
    ungranted_buyer: { permissions: [] },
    revoked_buyer: { permissions: ALL_PERMISSIONS, traits: [ :revoked ] }
  }.freeze

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
    @partnerships = PARTNERSHIPS.to_h do |buyer, spec|
      partnership = as(:supplier) do
        FactoryBot.create(:partnership, *spec.fetch(:traits, []), buyer_tenant_id: tenants[buyer], permissions: spec[:permissions])
      end
      [ buyer, partnership ]
    end
    as(:supplier) { FactoryBot.create(:item, :published) }
  end

  # supplier と buyer の取引関係
  def partnership(buyer) = @partnerships.fetch(buyer)

  def as(persona, &)
    Tenancy.with_tenant(tenants.fetch(persona), &)
  end

  # ペルソナがその表に所有する行の 1 つ
  def row(table, persona) = @rows.fetch(table).fetch(persona)

  def persona_of(tenant_id) = tenants.key(tenant_id) || tenant_id
end
