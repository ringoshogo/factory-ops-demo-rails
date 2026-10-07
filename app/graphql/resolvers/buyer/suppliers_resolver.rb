module Resolvers
  module Buyer
    # 経路 2。取引関係が失効すると空になる
    class SuppliersResolver < BaseResolver
      perspective :buyer
      authorize_with Partnerships::PartnershipPolicy, :list?

      type [ Types::SupplierPartnershipType ], null: false

      def resolve = Partnerships::Directory.for_buyer(current_user)
    end
  end
end
