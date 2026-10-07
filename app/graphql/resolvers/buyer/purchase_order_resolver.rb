module Resolvers
  module Buyer
    # 見えない ID は存在しない ID と同じく null
    class PurchaseOrderResolver < BaseResolver
      perspective :buyer
      authorize_with Purchasing::PurchaseOrderPolicy, :list?

      type Types::PurchaseOrderType, null: true
      argument :id, ID

      def resolve(id:) = Purchasing::PurchaseOrders.find(current_user, id)
    end
  end
end
