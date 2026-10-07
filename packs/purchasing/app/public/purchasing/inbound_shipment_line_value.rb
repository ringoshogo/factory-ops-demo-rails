module Purchasing
  InboundShipmentLineValue = Data.define(:id, :owner_tenant_id, :inbound_shipment_id, :purchase_order_line_id, :shipped_quantity)
end
