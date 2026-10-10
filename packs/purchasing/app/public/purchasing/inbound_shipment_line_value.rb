module Purchasing
  # accepted_quantity は検収数量で、検収の前は空
  InboundShipmentLineValue = Data.define(:id, :owner_tenant_id, :inbound_shipment_id, :purchase_order_line_id, :shipped_quantity,
    :accepted_quantity)
end
