module Resolvers
  module Supplier
    # 見えない ID は存在しない ID と同じく null
    class SalesOrderResolver < BaseResolver
      perspective :supplier
      authorize_with Sales::SalesOrderPolicy, :list?

      type Types::SalesOrderType, null: true
      argument :id, ID

      def resolve(id:) = Sales::SalesOrders.find(current_user, id)
    end
  end
end
