module Mutations
  # 失効させると、相手が読む経路と新しい発注が閉じる。失効した関係は再び有効にしない
  class RevokePartnership < BaseMutation
    perspective :supplier
    authorize_with Partnerships::PartnershipPolicy, :manage?
    audit "partnership.revoke", target: ->(target:, **) { target }, counterparty: ->(target:, **) { target.buyer.id }

    argument :partnership_id, ID
    result_field :partnership, Types::PartnershipType

    # 自社が受注側の関係だけを引く。見えない ID は NOT_FOUND になる
    def find_target(partnership_id:, **)
      Partnerships::Directory.partnership(current_user, partnership_id)
    end

    def perform(target, **)
      Partnerships::Management.revoke(current_user, partnership_id: target.id)
    end
  end
end
