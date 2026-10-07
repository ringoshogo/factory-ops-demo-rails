module Resolvers
  module Supplier
    class SalesOrdersResolver < BaseResolver
      perspective :supplier
      authorize_with Sales::SalesOrderPolicy, :list?

      type Types::SalesOrderType.connection_type, null: false

      def resolve
        Connections::PagedQuery.new { |first:, after:| Sales::SalesOrders.list(current_user, first:, after:) }
      end
    end
  end
end
