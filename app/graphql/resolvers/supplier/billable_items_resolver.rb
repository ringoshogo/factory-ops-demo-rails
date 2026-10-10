module Resolvers
  module Supplier
    # 未請求の請求対象明細。取引先で絞れ、取引先でないテナントで絞ると空になる
    class BillableItemsResolver < BaseResolver
      perspective :supplier
      authorize_with Billing::InvoicePolicy, :list?

      type Types::BillableItemType.connection_type, null: false
      argument :customer_tenant_id, ID, required: false

      def resolve(customer_tenant_id: nil)
        Connections::PagedQuery.new do |first:, after:|
          Billing::BillableItems.list(current_user, customer_tenant_id:, first:, after:)
        end
      end
    end
  end
end
