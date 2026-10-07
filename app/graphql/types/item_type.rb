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
  end
end
