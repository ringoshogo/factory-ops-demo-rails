module Mutations
  # 相手への place_orders は Purchasing::Ordering.place が確かめ、無ければ NOT_PERMITTED。
  # 存在しない・関係の無い・失効した・付与の無い相手を区別しない（docs/architecture/graphql-schema.md「ID と `node`」）
  class PlacePurchaseOrder < BaseMutation
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy, :place?

    argument :supplier_tenant_id, ID
    argument :desired_delivery_on, GraphQL::Types::ISO8601Date, required: false
    argument :lines, [ Types::PurchaseOrderLineInputType ]
    result_field :purchase_order, Types::PurchaseOrderType

    def perform(supplier_tenant_id:, lines:, desired_delivery_on: nil)
      Purchasing::Ordering.place(current_user, supplier_tenant_id:, desired_delivery_on:, lines: lines.map(&:to_h))
    end
  end
end
