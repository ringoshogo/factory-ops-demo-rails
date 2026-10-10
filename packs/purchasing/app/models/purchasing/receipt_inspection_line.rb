module Purchasing
  class ReceiptInspectionLine < TenantRecord
    belongs_to :receipt_inspection, inverse_of: :lines
    belongs_to :inbound_shipment_line
  end
end
