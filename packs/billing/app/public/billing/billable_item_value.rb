module Billing
  # 請求対象明細の値。連結元の発注明細 ID は相手側を指すので持たない。amount は単価 × 数量で、invoice_id が空なら未請求
  BillableItemValue = Data.define(:id, :owner_tenant_id, :customer_tenant_id, :shipment_id, :sales_order_line_id, :item_name,
    :unit_price, :quantity, :tax_rate_percent, :amount, :inspected_on, :invoice_id)
end
