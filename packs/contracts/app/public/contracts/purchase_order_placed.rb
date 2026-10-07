module Contracts
  # 発注登録（購買 → 受注）。lines は { purchase_order_line_id, part_number, quantity } の配列。
  # desired_delivery_on は ISO 8601 の日付の文字列か空
  PurchaseOrderPlaced = Event.define(:purchase_order_id, :buyer_tenant_id, :supplier_tenant_id, :desired_delivery_on, :lines)
end
