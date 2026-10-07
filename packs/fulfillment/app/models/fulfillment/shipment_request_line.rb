module Fulfillment
  # 出荷依頼の明細。sales_order_line_id・item_id は受注の行の、source_purchase_order_line_id は相手テナントの ID 参照
  class ShipmentRequestLine < TenantRecord
    belongs_to :shipment_request, inverse_of: :lines
  end
end
