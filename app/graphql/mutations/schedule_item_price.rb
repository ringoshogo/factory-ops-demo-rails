module Mutations
  # 自社の品目に、改定日からの単価を予約する。改定日は今日以降。発注側のカタログに見える単価を変えるので、admin に限り監査する
  # （docs/adr/006 決定 3、docs/architecture/context-map.md「自社の中の役割」）
  class ScheduleItemPrice < BaseMutation
    perspective :supplier
    authorize_with Sales::ItemPolicy, :change_price?
    audit "item_price.schedule", target: ->(target:, **) { target }, counterparty: nil

    argument :item_id, ID
    argument :unit_price, GraphQL::Types::BigInt
    argument :effective_on, GraphQL::Types::ISO8601Date
    result_field :item, Types::ItemType

    # 自社の品目だけを引く。見えない ID は NOT_FOUND になる
    def find_target(item_id:, **)
      Sales::Catalog.item(current_user, item_id)
    end

    def perform(target, unit_price:, effective_on:, **)
      Sales::ItemPrices.schedule(current_user, item_id: target.id, unit_price:, effective_on:)
    end
  end
end
