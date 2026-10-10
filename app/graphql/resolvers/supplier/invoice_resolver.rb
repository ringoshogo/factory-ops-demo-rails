module Resolvers
  module Supplier
    # 見えない ID は存在しない ID と同じく null
    class InvoiceResolver < BaseResolver
      perspective :supplier
      authorize_with Billing::InvoicePolicy, :list?

      type Types::InvoiceType, null: true
      argument :id, ID

      def resolve(id:) = Billing::Invoices.find(current_user, id)
    end
  end
end
