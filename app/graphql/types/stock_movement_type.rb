module Types
  # 在庫移動履歴の 1 行。引当の ID はフィールドに出さない
  class StockMovementType < BaseObject
    graphql_name "StockMovement"
    perspective :supplier
    authorize_with Inventory::StockPolicy

    field :id, ID, null: false
    field :item, ItemType, null: false
    field :type, StockMovementKindType, null: false
    field :quantity, Int, null: false
    field :reason, String
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    def item
      dataloader.with(Sources::PublicApiSource, Sales::Catalog, :items_for, context[:current_user]).load(object.item_id)
    end
  end
end
