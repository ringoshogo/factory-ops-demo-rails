module Purchasing
  # 入荷検収。入荷 1 件に 1 回
  class ReceiptInspection < TenantRecord
    belongs_to :inbound_shipment, inverse_of: :inspection
    has_many :lines, -> { order(:id) }, class_name: "Purchasing::ReceiptInspectionLine", inverse_of: :receipt_inspection
  end
end
