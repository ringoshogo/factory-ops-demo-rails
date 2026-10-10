module Purchasing
  # 発注。supplier_tenant_id は相手テナントへの ID 参照で、関連を張らない
  class PurchaseOrder < TenantRecord
    has_many :lines, -> { order(:id) }, class_name: "Purchasing::PurchaseOrderLine", inverse_of: :purchase_order
    has_many :inbound_shipments, -> { order(:id) }, class_name: "Purchasing::InboundShipment", inverse_of: :purchase_order
    has_many :cancellation_requests, -> { order(:id) }, class_name: "Purchasing::CancellationRequest", inverse_of: :purchase_order
  end
end
