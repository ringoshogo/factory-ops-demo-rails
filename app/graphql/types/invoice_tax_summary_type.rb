module Types
  # 請求書の税率ごとの課税対象額と、1 回だけ切り捨てた税額
  class InvoiceTaxSummaryType < BaseObject
    graphql_name "InvoiceTaxSummary"
    perspective :supplier
    authorize_with Billing::InvoicePolicy

    field :tax_rate_percent, Int, null: false
    field :taxable_amount, GraphQL::Types::BigInt, null: false
    field :tax_amount, GraphQL::Types::BigInt, null: false
  end
end
