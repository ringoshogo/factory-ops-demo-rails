module Contracts
  # 取消承認（受注 → 購買）。受注側の担当者が審査を承認し、受注を取り消した
  CancellationApproved = Event.define(:cancellation_request_id, :purchase_order_id, :buyer_tenant_id, :supplier_tenant_id)
end
