module Types
  # 受注側が所有する請求書
  class InvoiceType < BaseObject
    graphql_name "Invoice"
    perspective :supplier
    authorize_with Billing::InvoicePolicy

    field :id, ID, null: false
    field :invoice_number, String, description: "確定で振る。下書きは空"
    field :customer, TenantType, null: false
    field :period_start, GraphQL::Types::ISO8601Date, null: false
    field :period_end, GraphQL::Types::ISO8601Date, null: false
    field :state, InvoiceStateType, null: false
    field :issued_at, GraphQL::Types::ISO8601DateTime
    field :subtotal, GraphQL::Types::BigInt, null: false
    field :tax_total, GraphQL::Types::BigInt, null: false
    field :total, GraphQL::Types::BigInt, null: false
    field :tax_summaries, [ InvoiceTaxSummaryType ], null: false, description: "税率の昇順"
    field :items, resolver: Resolvers::Supplier::InvoiceItemsResolver

    def customer
      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :tenants, context[:current_user]).load(object.customer_tenant_id)
    end

    def tax_summaries
      dataloader.with(Sources::PublicApiSource, Billing::Invoices, :tax_summaries_for, context[:current_user]).load(object.id)
    end
  end
end
