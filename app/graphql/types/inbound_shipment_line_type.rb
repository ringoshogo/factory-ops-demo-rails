module Types
  class InboundShipmentLineType < BaseObject
    graphql_name "InboundShipmentLine"
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy

    field :id, ID, null: false
    field :purchase_order_line, PurchaseOrderLineType, null: false
    field :shipped_quantity, Int, null: false
    field :accepted_quantity, Int, description: "検収前は空"

    def purchase_order_line
      dataloader.with(Sources::PublicApiSource, Purchasing::PurchaseOrders, :lines_by_id, context[:current_user])
        .load(object.purchase_order_line_id)
    end
  end
end
