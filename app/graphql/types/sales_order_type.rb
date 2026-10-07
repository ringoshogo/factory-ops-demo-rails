module Types
  # 受注側が所有する受注。連結元の発注 ID など、相手側を指す ID はフィールドに出さない
  class SalesOrderType < BaseObject
    graphql_name "SalesOrder"
    perspective :supplier
    authorize_with Sales::SalesOrderPolicy

    field :id, ID, null: false
    field :order_no, String, null: false
    field :customer, TenantType, null: false
    field :order_date, GraphQL::Types::ISO8601Date, null: false
    field :due_date, GraphQL::Types::ISO8601Date
    field :status, SalesOrderStatusType, null: false
    field :lines, [ SalesOrderLineType ], null: false

    def customer
      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :tenants, context[:current_user])
        .load(object.customer_tenant_id)
    end

    def lines
      dataloader.with(Sources::PublicApiSource, Sales::SalesOrders, :lines_for, context[:current_user]).load(object.id)
    end
  end
end
