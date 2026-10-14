module Purchasing
  # 発注の値。status は PurchaseOrderStatus が導出した記号。cancellation_pending は回答待ちの取消依頼があるか（取消依頼中）で、
  # 状況に重ねて示す（docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
  # total_amount は PurchaseOrderAmount が計算した税抜の合計金額（Integer）で、受注確定の前の明細を含めば nil
  PurchaseOrderValue = Data.define(:id, :owner_tenant_id, :order_no, :supplier_tenant_id, :order_date, :desired_delivery_on,
    :status, :cancellation_pending, :total_amount)
end
