module Types
  # 請求書の単価の説明（docs/adr/006 決定 5）。請求対象明細のフィールドとしてだけ現れる
  class PriceExplanationType < BaseObject
    graphql_name "PriceExplanation"
    perspective :supplier
    authorization_exempt reason: "自社の受注明細の単価だけを持ち、認可済みの BillableItem のフィールドとしてだけ現れる"

    field :ordered_unit_price, GraphQL::Types::BigInt, null: false, description: "受注明細に写した単価"
    field :priced_on, GraphQL::Types::ISO8601Date, null: false, description: "受注明細が単価を引いた有効日"
    field :unit_price_as_of_issue, GraphQL::Types::BigInt, description: "請求書の発行の時点で、pricedOn の単価として信じていた値"
    field :unit_price_now, GraphQL::Types::BigInt, null: false, description: "いま分かっている、pricedOn の単価"
  end
end
