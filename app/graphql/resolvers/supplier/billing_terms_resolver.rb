module Resolvers
  module Supplier
    class BillingTermsResolver < BaseResolver
      perspective :supplier
      authorize_with Billing::InvoicePolicy, :list?

      type [ Types::BillingTermType ], null: false

      def resolve = Billing::Terms.list(current_user)
    end
  end
end
