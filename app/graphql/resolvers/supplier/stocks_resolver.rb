module Resolvers
  module Supplier
    class StocksResolver < BaseResolver
      perspective :supplier
      authorize_with Inventory::StockPolicy, :list?

      type Types::StockType.connection_type, null: false

      def resolve
        Connections::PagedQuery.new { |first:, after:| Inventory::Stocks.list(current_user, first:, after:) }
      end
    end
  end
end
