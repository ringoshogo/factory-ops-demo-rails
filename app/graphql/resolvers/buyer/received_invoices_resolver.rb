module Resolvers
  module Buyer
    class ReceivedInvoicesResolver < BaseResolver
      perspective :buyer
      authorize_with Purchasing::PurchaseOrderPolicy, :list?

      type Types::ReceivedInvoiceType.connection_type, null: false

      def resolve
        Connections::PagedQuery.new { |first:, after:| Purchasing::ReceivedInvoices.list(current_user, first:, after:) }
      end
    end
  end
end
