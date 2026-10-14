module Resolvers
  module Buyer
    class PurchaseOrdersResolver < BaseResolver
      include SortArguments

      perspective :buyer
      authorize_with Purchasing::PurchaseOrderPolicy, :list?

      type Types::PurchaseOrderType.connection_type, null: false
      sort_arguments Types::PurchaseOrderOrderType
      argument :filter, Types::PurchaseOrderFilterType, required: false

      def resolve(order_by: nil, then_by: nil, filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Purchasing::PurchaseOrders.list(current_user, first:, after:, order_by: sort_list(order_by, then_by), filter: filter.to_h)
        end
      end
    end
  end
end
