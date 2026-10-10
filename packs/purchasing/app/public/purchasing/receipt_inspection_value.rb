module Purchasing
  ReceiptInspectionValue = Data.define(:id, :owner_tenant_id, :inbound_shipment_id, :inspected_on)
end
