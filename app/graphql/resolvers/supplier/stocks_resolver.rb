module Resolvers
  module Supplier
    class StocksResolver < BaseResolver
      include SortArguments

      perspective :supplier
      authorize_with Inventory::StockPolicy, :list?

      type Types::StockType.connection_type, null: false
      sort_arguments Types::StockOrderType
      argument :filter, Types::StockFilterType, required: false

      def resolve(order_by: nil, then_by: nil, filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Inventory::Stocks.list(current_user, first:, after:, order_by: sort_list(order_by, then_by), filter: filter.to_h)
        end
      end
    end
  end
end
