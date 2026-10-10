module Fulfillment
  # 出荷実績。buyer_tenant_id・source_purchase_order_id は、発注側が自社の発注に連結した出荷を読む経路 3 のための写し
  # （docs/architecture/data-model.md「出荷（`fulfillment`）」）
  class Shipment < TenantRecord
    belongs_to :shipment_request, inverse_of: :shipment
    belongs_to :shipping_instruction
    has_many :lines, -> { order(:id) }, class_name: "Fulfillment::ShipmentLine", inverse_of: :shipment
  end
end
