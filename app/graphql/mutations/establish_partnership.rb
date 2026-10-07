module Mutations
  # 相手は発注側テナントの取引用コードで指定する。一致するテナントが無ければ NOT_FOUND
  class EstablishPartnership < BaseMutation
    perspective :supplier
    authorize_with Partnerships::PartnershipPolicy, :establish?

    argument :partner_code, String
    result_field :partnership, Types::PartnershipType

    def perform(partner_code:)
      Partnerships::Management.establish(current_user, partner_code:)
    end
  end
end
