module Fulfillment
  # 出荷依頼の値。連結元の発注 ID は相手側を指すので持たない。status は ShipmentRequestStatus が導出した記号
  ShipmentRequestValue = Data.define(:id, :owner_tenant_id, :sales_order_id, :buyer_tenant_id, :due_date, :status)
end
