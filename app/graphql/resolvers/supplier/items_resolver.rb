module Resolvers
  module Supplier
    class ItemsResolver < BaseResolver
      include SortArguments

      perspective :supplier
      authorize_with Sales::ItemPolicy, :list?

      type Types::ItemType.connection_type, null: false
      sort_arguments Types::ItemOrderType
      argument :filter, Types::ItemFilterType, required: false

      def resolve(order_by: nil, then_by: nil, filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Sales::Catalog.items(current_user, first:, after:, order_by: sort_list(order_by, then_by), filter: filter.to_h)
        end
      end
    end
  end
end
