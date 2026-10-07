module Fulfillment
  ShippingInstructionValue = Data.define(:id, :owner_tenant_id, :shipment_request_id, :planned_date)
end
