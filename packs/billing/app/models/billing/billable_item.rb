module Billing
  # 請求対象明細。受注が検収で確定した明細で、invoice_id が空なら未請求。shipment_id・sales_order_line_id・
  # source_purchase_order_line_id は他のコンテキストか相手テナントへの ID 参照で、関連を張らない
  class BillableItem < TenantRecord
    belongs_to :invoice, optional: true, inverse_of: :items

    scope :unbilled, -> { where(invoice_id: nil) }

    def amount = unit_price * quantity
  end
end
