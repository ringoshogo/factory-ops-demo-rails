module Purchasing
  # 受領請求書の明細の値
  ReceivedInvoiceLineValue = Data.define(:id, :owner_tenant_id, :received_invoice_id, :purchase_order_line_id, :item_name, :unit_price,
    :quantity, :tax_rate_percent, :amount)
end
