module Types
  # 販売単価の 1 行（docs/adr/006）。受注側だけが読み、発注側には今日の単価だけをカタログで見せる
  class ItemPriceType < BaseObject
    graphql_name "ItemPrice"
    description "販売単価の 1 行（adr/006）。validFrom は含み validTo は含まない。validFrom・validTo・recordedTo の空は、上限なしを表す"
    perspective :supplier
    authorize_with Sales::ItemPolicy

    field :id, ID, null: false
    field :unit_price, GraphQL::Types::BigInt, null: false
    field :valid_from, GraphQL::Types::ISO8601Date
    field :valid_to, GraphQL::Types::ISO8601Date
    field :recorded_from, GraphQL::Types::ISO8601DateTime, null: false
    field :recorded_to, GraphQL::Types::ISO8601DateTime
    field :reason, String
  end
end
