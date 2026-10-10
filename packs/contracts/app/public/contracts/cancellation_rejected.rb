module Contracts
  # 取消却下（受注 → 購買）。受注側の担当者が審査を却下したか、依頼が届いた時点で受注が出荷済みか取消済だった
  CancellationRejected = Event.define(:cancellation_request_id, :purchase_order_id, :buyer_tenant_id, :supplier_tenant_id)
end
