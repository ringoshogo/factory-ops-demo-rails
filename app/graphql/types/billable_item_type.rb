module Types
  # 受注側が所有する請求対象明細（「請求対象確定」の写し）。連結元の発注明細 ID はフィールドに出さない
  class BillableItemType < BaseObject
    graphql_name "BillableItem"
    perspective :supplier
    authorize_with Billing::InvoicePolicy

    field :id, ID, null: false
    field :customer, TenantType, null: false
    field :sales_order_line, SalesOrderLineType, null: false
    field :item_name, String, null: false
    field :unit_price, GraphQL::Types::BigInt, null: false
    field :quantity, Int, null: false, description: "検収数量"
    field :tax_rate_percent, Int, null: false
    field :amount, GraphQL::Types::BigInt, null: false, description: "単価 × 検収数量。税を含まない"
    field :inspected_on, GraphQL::Types::ISO8601Date, null: false

    def customer
      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :tenants, context[:current_user]).load(object.customer_tenant_id)
    end

    # 請求は受注に依存しないので、ルートパッケージで受注の公開 API を呼ぶ
    def sales_order_line
      dataloader.with(Sources::PublicApiSource, Sales::SalesOrders, :lines_by_ids, context[:current_user]).load(object.sales_order_line_id)
    end
  end
end
