module Resolvers
  module Supplier
    class ItemsResolver < BaseResolver
      perspective :supplier
      authorize_with Sales::ItemPolicy, :list?

      type Types::ItemType.connection_type, null: false

      def resolve
        Connections::PagedQuery.new { |first:, after:| Sales::Catalog.items(current_user, first:, after:) }
      end
    end
  end
end
