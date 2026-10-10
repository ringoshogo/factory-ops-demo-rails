module Contracts
  # 出荷停止（受注 → 出荷）。取消の審査の間、受注の出荷指示の作成と出荷の計上を止める
  ShippingHeld = Event.define(:cancellation_review_id, :sales_order_id, :supplier_tenant_id)
end
