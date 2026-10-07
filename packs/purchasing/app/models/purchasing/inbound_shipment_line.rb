module Purchasing
  class InboundShipmentLine < TenantRecord
    belongs_to :inbound_shipment, inverse_of: :lines
    belongs_to :purchase_order_line
  end
end
