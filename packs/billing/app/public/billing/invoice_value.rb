module Billing
  # 請求書の値。state は :draft（issued_at が空）か :issued。下書きの invoice_number は空
  InvoiceValue = Data.define(:id, :owner_tenant_id, :customer_tenant_id, :invoice_number, :period_start, :period_end, :issued_at,
    :state, :subtotal, :tax_total, :total)
end
