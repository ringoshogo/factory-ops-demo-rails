module Resolvers
  module Supplier
    class InvoicesResolver < BaseResolver
      perspective :supplier
      authorize_with Billing::InvoicePolicy, :list?

      type Types::InvoiceType.connection_type, null: false

      def resolve
        Connections::PagedQuery.new { |first:, after:| Billing::Invoices.list(current_user, first:, after:) }
      end
    end
  end
end
