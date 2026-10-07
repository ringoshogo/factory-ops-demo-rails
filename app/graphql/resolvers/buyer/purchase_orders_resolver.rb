module Resolvers
  module Buyer
    class PurchaseOrdersResolver < BaseResolver
      perspective :buyer
      authorize_with Purchasing::PurchaseOrderPolicy, :list?

      type Types::PurchaseOrderType.connection_type, null: false

      def resolve
        Connections::PagedQuery.new { |first:, after:| Purchasing::PurchaseOrders.list(current_user, first:, after:) }
      end
    end
  end
end
