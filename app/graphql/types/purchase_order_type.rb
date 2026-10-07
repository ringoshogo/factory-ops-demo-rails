module Types
  # 発注側が所有する発注。相手の受注へたどるフィールドは持たず、還流した状況と写しだけを見せる
  class PurchaseOrderType < BaseObject
    graphql_name "PurchaseOrder"
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy

    field :id, ID, null: false
    field :order_no, String, null: false
    field :supplier, TenantType, null: false
    field :order_date, GraphQL::Types::ISO8601Date, null: false
    field :desired_delivery_on, GraphQL::Types::ISO8601Date
    field :status, PurchaseOrderStatusType, null: false
    field :lines, [ PurchaseOrderLineType ], null: false

    def supplier
      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :tenants, context[:current_user])
        .load(object.supplier_tenant_id)
    end

    def lines
      dataloader.with(Sources::PublicApiSource, Purchasing::PurchaseOrders, :lines_for, context[:current_user]).load(object.id)
    end
  end
end
