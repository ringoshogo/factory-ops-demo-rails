module Resolvers
  module Supplier
    class StockMovementsResolver < BaseResolver
      perspective :supplier
      authorize_with Inventory::StockPolicy, :list?

      type Types::StockMovementType.connection_type, null: false
      argument :item_id, ID, required: false
      argument :filter, Types::StockMovementFilterType, required: false

      def resolve(item_id: nil, filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Inventory::Stocks.movements(current_user, item_id:, first:, after:, filter: filter.to_h)
        end
      end
    end
  end
end
