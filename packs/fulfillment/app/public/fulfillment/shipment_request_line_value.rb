module Fulfillment
  # 出荷依頼の明細の値。連結元の発注明細 ID は相手側を指すので持たない
  ShipmentRequestLineValue = Data.define(:id, :owner_tenant_id, :shipment_request_id, :sales_order_line_id, :item_id, :quantity)
end
