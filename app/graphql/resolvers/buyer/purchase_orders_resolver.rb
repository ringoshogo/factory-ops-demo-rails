module Resolvers
  module Buyer
    class PurchaseOrdersResolver < BaseResolver
      perspective :buyer
      authorize_with Purchasing::PurchaseOrderPolicy, :list?

      type Types::PurchaseOrderType.connection_type, null: false
      argument :order_by, Types::PurchaseOrderOrderType, required: false
      argument :filter, Types::PurchaseOrderFilterType, required: false

      def resolve(order_by: nil, filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Purchasing::PurchaseOrders.list(current_user, first:, after:, order_by: order_by&.to_h, filter: filter.to_h)
        end
      end
    end
  end
end
