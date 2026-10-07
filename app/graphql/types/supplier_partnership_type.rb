module Types
  # 経路 2。自社が発注側である有効な取引関係。取引関係 ID は返さず、受注側テナントで識別する
  class SupplierPartnershipType < BaseObject
    graphql_name "SupplierPartnership"
    perspective :buyer
    cross_tenant_read :partnerships
    authorize_with Partnerships::PartnershipPolicy, :show_to_buyer?

    field :supplier, TenantType, null: false
    field :permissions, [ PartnershipPermissionType ], null: false
    field :catalog, resolver: Resolvers::Buyer::CatalogResolver, description: "経路 1。view_catalog が無ければ空"
  end
end
