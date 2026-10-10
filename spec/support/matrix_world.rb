require_relative "tenant_helpers"

# 行列テストの世界（docs/architecture/context-map.md「テナントと所有」、docs/architecture/data-model.md「RLS」）。ペルソナごとにテナントと admin のユーザーを作り、
# テナントの表ごとに、どのペルソナも自社の行を factory で 1 件以上持つようにする。
# そのうえで、supplier が受注側になる取引関係を 3 つ結び、supplier の公開品目を 1 件足す
# （表ごとの行は factory の既定のままなので、品目は公開しない）。
# さらに supplier と取引関係を結んだ発注側ごとに、supplier への発注と、それに連結した supplier の受注と出荷実績を 1 組足す。
# 連結元の ID を持ち合う行でも、相手からは見えないことと、出荷実績を読む経路 3 が付与と失効に従うことを確かめるためである
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
    @linked_orders = PARTNERSHIPS.keys.index_with { |buyer| link_orders(buyer) }
  end

  # supplier と buyer の取引関係
  def partnership(buyer) = @partnerships.fetch(buyer)

  # buyer の発注と、それに連結した supplier の受注と出荷実績（:purchase_order・:sales_order・:shipment）
  def linked_order(side, buyer = :granted_buyer) = @linked_orders.fetch(buyer).fetch(side)

  def as(persona, &)
    Tenancy.with_tenant(tenants.fetch(persona), &)
  end

  # ペルソナがその表に所有する行の 1 つ
  def row(table, persona) = @rows.fetch(table).fetch(persona)

  def persona_of(tenant_id) = tenants.key(tenant_id) || tenant_id

  private

  # 受注側の ACL が「発注登録」から作るのと同じ形に、発注と受注を明細ごと連結し、
  # 出荷が「出荷可能」から作るのと同じ形に、受注を全量で出荷する
  def link_orders(buyer)
    purchase_order = as(buyer) { FactoryBot.create(:purchase_order, supplier_tenant_id: tenants[:supplier]) }
    purchase_order_line = as(buyer) { FactoryBot.create(:purchase_order_line, purchase_order:) }
    as(:supplier) do
      sales_order = FactoryBot.create(:sales_order, customer_tenant_id: tenants[buyer], source_purchase_order_id: purchase_order.id)
      sales_order_line = FactoryBot.create(:sales_order_line, :matched, sales_order:,
        source_purchase_order_line_id: purchase_order_line.id, customer_part_number: purchase_order_line.part_number)
      request = FactoryBot.create(:shipment_request, sales_order_id: sales_order.id, buyer_tenant_id: tenants[buyer],
        source_purchase_order_id: purchase_order.id)
      request_line = FactoryBot.create(:shipment_request_line, shipment_request: request, sales_order_line_id: sales_order_line.id,
        source_purchase_order_line_id: purchase_order_line.id, item_id: sales_order_line.item_id)
      shipment = FactoryBot.create(:shipment, shipping_instruction: FactoryBot.create(:shipping_instruction, shipment_request: request))
      FactoryBot.create(:shipment_line, shipment:, shipment_request_line: request_line)
      { purchase_order:, sales_order:, shipment: }
    end
  end
end
