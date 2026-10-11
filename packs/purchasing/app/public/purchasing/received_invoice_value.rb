module Purchasing
  # 受領請求書の値。受注側の請求書 ID は持たない（docs/architecture/graphql-schema.md「発注側の視点」）
  ReceivedInvoiceValue = Data.define(:id, :owner_tenant_id, :supplier_tenant_id, :invoice_number, :period_start, :period_end, :issued_on,
    :subtotal, :tax_total, :total)
end
