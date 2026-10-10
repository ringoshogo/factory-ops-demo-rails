module Mutations
  class GrantPermission < BaseMutation
    perspective :supplier
    authorize_with Partnerships::PartnershipPolicy, :manage?
    audit "partnership.grant_permission", target: ->(target:, **) { target }, counterparty: ->(target:, **) { target.buyer.id }

    argument :partnership_id, ID
    argument :permission, Types::PartnershipPermissionType
    result_field :partnership, Types::PartnershipType

    # 自社が受注側の関係だけを引く。見えない ID は NOT_FOUND になる
    def find_target(partnership_id:, **)
      Partnerships::Directory.partnership(current_user, partnership_id)
    end

    def perform(target, permission:, **)
      Partnerships::Management.grant(current_user, partnership_id: target.id, permission:)
    end
  end
end
