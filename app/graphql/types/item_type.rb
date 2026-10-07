module Types
  # 受注側が所有する品目。公開していないものも含む
  class ItemType < BaseObject
    graphql_name "Item"
    perspective :supplier
    authorize_with Sales::ItemPolicy

    field :id, ID, null: false
    field :code, String, null: false
    field :name, String, null: false
    field :unit, String, null: false
    field :unit_price, GraphQL::Types::BigInt, null: false
    field :tax_rate_percent, Int, null: false
    field :published, Boolean, null: false
    field :stock, StockType, description: "入出庫も引当もしていない品目は空"

    def stock
      dataloader.with(Sources::PublicApiSource, Inventory::Stocks, :for_items, context[:current_user]).load(object.id)
    end
  end
end
