module Purchasing
  # 発注の値。status は PurchaseOrderStatus が導出した記号。cancellation_pending は回答待ちの取消依頼があるか（取消依頼中）で、
  # 状況に重ねて示す（docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）
  PurchaseOrderValue = Data.define(:id, :owner_tenant_id, :order_no, :supplier_tenant_id, :order_date, :desired_delivery_on,
    :status, :cancellation_pending)
end
