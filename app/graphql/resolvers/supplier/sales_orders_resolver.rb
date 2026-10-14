module Resolvers
  module Supplier
    class SalesOrdersResolver < BaseResolver
      include SortArguments

      perspective :supplier
      authorize_with Sales::SalesOrderPolicy, :list?

      type Types::SalesOrderType.connection_type, null: false
      sort_arguments Types::SalesOrderOrderType
      argument :filter, Types::SalesOrderFilterType, required: false

      def resolve(order_by: nil, then_by: nil, filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Sales::SalesOrders.list(current_user, first:, after:, order_by: sort_list(order_by, then_by), filter: filter.to_h)
        end
      end
    end
  end
end
