module Billing
  # 請求書の税率ごとの課税対象額と税額
  class InvoiceTaxSummary < TenantRecord
    belongs_to :invoice, inverse_of: :tax_summaries
  end
end
