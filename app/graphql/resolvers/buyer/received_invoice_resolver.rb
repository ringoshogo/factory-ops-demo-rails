module Resolvers
  module Buyer
    # 見えない ID は存在しない ID と同じく null
    class ReceivedInvoiceResolver < BaseResolver
      perspective :buyer
      authorize_with Purchasing::PurchaseOrderPolicy, :list?

      type Types::ReceivedInvoiceType, null: true
      argument :id, ID

      def resolve(id:) = Purchasing::ReceivedInvoices.find(current_user, id)
    end
  end
end
