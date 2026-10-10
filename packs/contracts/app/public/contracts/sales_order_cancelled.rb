module Contracts
  # 受注取消（受注 → 購買）。受注側が、審査を経ずに自社の都合で受注を取り消した。出荷へは別に「出荷取消」を出す
  SalesOrderCancelled = Event.define(:purchase_order_id, :buyer_tenant_id, :supplier_tenant_id)
end
