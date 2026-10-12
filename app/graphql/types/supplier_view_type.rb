module Types
  # 受注側の視点。受注・在庫・出荷・請求・取引関係が所有するデータを持つ
  class SupplierViewType < BaseObject
    graphql_name "SupplierView"
    perspective :supplier
    authorization_exempt reason: "データを持たない入口。フィールドはすべてリゾルバで、各自が宣言する"

    field :partnerships, resolver: Resolvers::Supplier::PartnershipsResolver
    field :items, resolver: Resolvers::Supplier::ItemsResolver
    field :item, resolver: Resolvers::Supplier::ItemResolver
    field :part_mappings, resolver: Resolvers::Supplier::PartMappingsResolver
    field :sales_orders, resolver: Resolvers::Supplier::SalesOrdersResolver
    field :sales_order, resolver: Resolvers::Supplier::SalesOrderResolver
    field :stocks, resolver: Resolvers::Supplier::StocksResolver
    field :stock_movements, resolver: Resolvers::Supplier::StockMovementsResolver
    field :shipment_requests, resolver: Resolvers::Supplier::ShipmentRequestsResolver
    field :billing_terms, resolver: Resolvers::Supplier::BillingTermsResolver
    field :billable_items, resolver: Resolvers::Supplier::BillableItemsResolver, description: "未請求の請求対象明細"
    field :invoices, resolver: Resolvers::Supplier::InvoicesResolver
    field :invoice, resolver: Resolvers::Supplier::InvoiceResolver
    field :dashboard, resolver: Resolvers::Supplier::DashboardResolver
    field :imports, resolver: Resolvers::Supplier::ImportsResolver
    field :import, resolver: Resolvers::Supplier::ImportResolver
  end
end
