module Resolvers
  module Supplier
    class PartnershipsResolver < BaseResolver
      perspective :supplier
      authorize_with Partnerships::PartnershipPolicy, :list?

      type [ Types::PartnershipType ], null: false

      def resolve = Partnerships::Directory.for_supplier(current_user)
    end
  end
end
