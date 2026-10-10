module Purchasing
  # 入荷。「出荷計上」の写しで、shipment_id は受注側テナントの出荷実績への ID 参照。関連を張らない
  class InboundShipment < TenantRecord
    belongs_to :purchase_order, inverse_of: :inbound_shipments
    has_many :lines, -> { order(:id) }, class_name: "Purchasing::InboundShipmentLine", inverse_of: :inbound_shipment
    has_one :inspection, class_name: "Purchasing::ReceiptInspection", inverse_of: :inbound_shipment
  end
end
