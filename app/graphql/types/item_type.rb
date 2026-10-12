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
    field :unit_price, GraphQL::Types::BigInt, null: false, description: "今日の販売単価"
    field :prices, [ ItemPriceType ], null: false,
      description: "単価の履歴。asOf の時点で正しいと信じていた行を、有効期間の順に返す。省けばいま" do
      argument :as_of, GraphQL::Types::ISO8601DateTime, required: false
    end
    field :tax_rate_percent, Int, null: false
    field :published, Boolean, null: false
    field :stock, StockType, description: "入出庫も引当もしていない品目は空"

    def prices(as_of: nil)
      dataloader.with(Sources::PublicApiSource, Sales::ItemPrices, :history, context[:current_user], as_of:).load(object.id)
    end

    def stock
      dataloader.with(Sources::PublicApiSource, Inventory::Stocks, :for_items, context[:current_user]).load(object.id)
    end
  end
end
