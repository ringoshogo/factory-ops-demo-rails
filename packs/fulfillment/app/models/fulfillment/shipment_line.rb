module Fulfillment
  # 出荷実績の明細。source_purchase_order_line_id は、出荷明細を発注明細に結び付けるための写し
  class ShipmentLine < TenantRecord
    belongs_to :shipment, inverse_of: :lines
    belongs_to :shipment_request_line
  end
end
