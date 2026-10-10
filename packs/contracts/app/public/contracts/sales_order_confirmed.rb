module Contracts
  # 受注確定（受注 → 購買）。lines は { purchase_order_line_id, item_name, unit_price } の配列で、unit_price は円の整数の文字列。
  # 受注・受注明細・品目の ID は運ばない（docs/architecture/data-model.md「購買（`purchasing`）」）
  SalesOrderConfirmed = Event.define(:purchase_order_id, :buyer_tenant_id, :supplier_tenant_id, :lines)
end
