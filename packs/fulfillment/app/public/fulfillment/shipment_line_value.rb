module Fulfillment
  ShipmentLineValue = Data.define(:id, :owner_tenant_id, :shipment_id, :shipment_request_line_id, :quantity)
end
