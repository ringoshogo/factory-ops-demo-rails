module Resolvers
  module Supplier
    class StocksResolver < BaseResolver
      perspective :supplier
      authorize_with Inventory::StockPolicy, :list?

      type Types::StockType.connection_type, null: false
      argument :order_by, Types::StockOrderType, required: false
      argument :filter, Types::StockFilterType, required: false

      def resolve(order_by: nil, filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Inventory::Stocks.list(current_user, first:, after:, order_by: order_by&.to_h, filter: filter.to_h)
        end
      end
    end
  end
end
