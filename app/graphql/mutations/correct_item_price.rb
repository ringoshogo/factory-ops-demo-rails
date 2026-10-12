module Mutations
  # 自社の単価の現在の行を、同じ有効期間で正しい単価に訂正する。理由は必須。閉じた行は CONFLICT。
  # 発注側のカタログに見える単価を変えうるので、admin に限り監査する（docs/adr/006 決定 3、docs/architecture/context-map.md「自社の中の役割」）
  class CorrectItemPrice < BaseMutation
    perspective :supplier
    authorize_with Sales::ItemPolicy, :change_price?
    audit "item_price.correct", target: ->(target:, **) { target }, counterparty: nil

    argument :item_price_id, ID
    argument :unit_price, GraphQL::Types::BigInt
    argument :reason, String
    result_field :item, Types::ItemType

    # 自社の単価の行だけを引く。見えない ID は NOT_FOUND になる
    def find_target(item_price_id:, **)
      Sales::ItemPrices.find(current_user, item_price_id)
    end

    def perform(target, unit_price:, reason:, **)
      Sales::ItemPrices.correct(current_user, item_price_id: target.id, unit_price:, reason:)
    end
  end
end
