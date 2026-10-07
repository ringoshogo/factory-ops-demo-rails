module Types
  # 受注側の視点。受注・在庫・出荷・請求・取引関係が所有するデータを持つ
  class SupplierViewType < BaseObject
    graphql_name "SupplierView"
    perspective :supplier
    authorization_exempt reason: "データを持たない入口。フィールドはすべてリゾルバで、各自が宣言する"

    field :partnerships, resolver: Resolvers::Supplier::PartnershipsResolver
    field :items, resolver: Resolvers::Supplier::ItemsResolver
    field :part_mappings, resolver: Resolvers::Supplier::PartMappingsResolver
    field :sales_orders, resolver: Resolvers::Supplier::SalesOrdersResolver
    field :sales_order, resolver: Resolvers::Supplier::SalesOrderResolver
  end
end
