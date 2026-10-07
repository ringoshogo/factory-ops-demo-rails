module Types
  class SalesOrderLineType < BaseObject
    graphql_name "SalesOrderLine"
    perspective :supplier
    authorize_with Sales::SalesOrderPolicy

    field :id, ID, null: false
    field :customer_part_number, String, null: false
    field :item, ItemType, description: "照合前は空"
    field :item_name, String
    field :unit_price, GraphQL::Types::BigInt
    field :tax_rate_percent, Int
    field :quantity, Int, null: false
    field :allocated_quantity, Int, null: false

    def item
      return unless object.item_id

      dataloader.with(Sources::PublicApiSource, Sales::Catalog, :items_for, context[:current_user]).load(object.item_id)
    end
  end
end
