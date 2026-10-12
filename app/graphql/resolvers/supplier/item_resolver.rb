module Resolvers
  module Supplier
    # 見えない ID は存在しない ID と同じく null
    class ItemResolver < BaseResolver
      perspective :supplier
      authorize_with Sales::ItemPolicy, :list?

      type Types::ItemType, null: true
      argument :id, ID

      def resolve(id:) = Sales::Catalog.item(current_user, id)
    end
  end
end
