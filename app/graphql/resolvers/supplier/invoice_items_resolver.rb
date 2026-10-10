module Resolvers
  module Supplier
    # 請求書に集めた請求対象明細
    class InvoiceItemsResolver < BaseResolver
      perspective :supplier
      authorize_with Billing::InvoicePolicy, :list?

      type Types::BillableItemType.connection_type, null: false

      def resolve
        Connections::PagedQuery.new { |first:, after:| Billing::BillableItems.for_invoice(current_user, object.id, first:, after:) }
      end
    end
  end
end
