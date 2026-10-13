module Resolvers
  module Supplier
    class SalesOrdersResolver < BaseResolver
      perspective :supplier
      authorize_with Sales::SalesOrderPolicy, :list?

      type Types::SalesOrderType.connection_type, null: false
      argument :order_by, Types::SalesOrderOrderType, required: false
      argument :filter, Types::SalesOrderFilterType, required: false

      def resolve(order_by: nil, filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Sales::SalesOrders.list(current_user, first:, after:, order_by: order_by&.to_h, filter: filter.to_h)
        end
      end
    end
  end
end
