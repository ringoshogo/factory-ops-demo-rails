module Resolvers
  module Supplier
    class ItemsResolver < BaseResolver
      perspective :supplier
      authorize_with Sales::ItemPolicy, :list?

      type Types::ItemType.connection_type, null: false
      argument :order_by, Types::ItemOrderType, required: false
      argument :filter, Types::ItemFilterType, required: false

      def resolve(order_by: nil, filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Sales::Catalog.items(current_user, first:, after:, order_by: order_by&.to_h, filter: filter.to_h)
        end
      end
    end
  end
end
