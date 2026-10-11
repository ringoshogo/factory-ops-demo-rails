module Purchasing
  # 受領請求書。「請求書発行」の写しで、invoice_id と supplier_tenant_id は相手テナントへの ID 参照なので、関連を張らない
  class ReceivedInvoice < TenantRecord
    has_many :lines, -> { order(:id) }, class_name: "Purchasing::ReceivedInvoiceLine", inverse_of: :received_invoice
  end
end
