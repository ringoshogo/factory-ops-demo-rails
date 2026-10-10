module Billing
  # 請求書。issued_at が空なら下書き。customer_tenant_id は相手テナントへの ID 参照で、関連を張らない
  class Invoice < TenantRecord
    has_many :items, -> { order(:id) }, class_name: "Billing::BillableItem", inverse_of: :invoice
    has_many :tax_summaries, -> { order(:tax_rate_percent) }, class_name: "Billing::InvoiceTaxSummary", inverse_of: :invoice

    scope :draft, -> { where(issued_at: nil) }
    scope :issued, -> { where.not(issued_at: nil) }

    def draft? = issued_at.nil?
  end
end
