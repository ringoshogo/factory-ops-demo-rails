module Billing
  # 請求書の税率ごとの課税対象額と税額の値
  InvoiceTaxSummaryValue = Data.define(:invoice_id, :owner_tenant_id, :tax_rate_percent, :taxable_amount, :tax_amount)
end
