module Purchasing
  # 受領請求書の明細。自社の発注明細を指す
  class ReceivedInvoiceLine < TenantRecord
    belongs_to :received_invoice, inverse_of: :lines
    belongs_to :purchase_order_line
  end
end
