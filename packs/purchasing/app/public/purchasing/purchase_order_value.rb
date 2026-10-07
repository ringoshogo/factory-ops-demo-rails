module Purchasing
  # 発注の値。status は PurchaseOrderStatus が導出した記号
  PurchaseOrderValue = Data.define(:id, :owner_tenant_id, :order_no, :supplier_tenant_id, :order_date, :desired_delivery_on,
    :status)
end
