module Types
  class ShipmentRequestLineType < BaseObject
    graphql_name "ShipmentRequestLine"
    perspective :supplier
    authorize_with Fulfillment::ShipmentRequestPolicy

    field :id, ID, null: false
    field :sales_order_line, SalesOrderLineType, null: false
    field :item, ItemType, null: false
    field :quantity, Int, null: false

    def sales_order_line
      dataloader.with(Sources::PublicApiSource, Sales::SalesOrders, :lines_by_ids, context[:current_user]).load(object.sales_order_line_id)
    end

    def item
      dataloader.with(Sources::PublicApiSource, Sales::Catalog, :items_for, context[:current_user]).load(object.item_id)
    end
  end
end
