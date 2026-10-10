module Contracts
  # 出荷停止解除（受注 → 出荷）。審査が却下で決着した
  ShippingHoldReleased = Event.define(:cancellation_review_id, :sales_order_id, :supplier_tenant_id)
end
