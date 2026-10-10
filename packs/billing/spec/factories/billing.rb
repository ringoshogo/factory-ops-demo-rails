FactoryBot.define do
  # どれも Tenancy.with_tenant の中で、受注側のテナントで作る。取引先・出荷実績・受注明細・発注明細は ID で参照するだけなので、作らない
  factory :billing_term, class: "Billing::BillingTerm" do
    owner_tenant_id { Current.tenant_id }
    customer_tenant_id { FactoryBot.create(:tenant).id }
    closing_day { 31 }
  end

  # 既定は未請求
  factory :billable_item, class: "Billing::BillableItem" do
    owner_tenant_id { Current.tenant_id }
    customer_tenant_id { FactoryBot.create(:tenant).id }
    shipment_id { SecureRandom.uuid }
    sales_order_line_id { SecureRandom.uuid }
    source_purchase_order_line_id { SecureRandom.uuid }
    item_name { "六角ボルト M8" }
    unit_price { 120 }
    quantity { 1 }
    tax_rate_percent { 10 }
    inspected_on { Date.current }
  end

  # 既定は下書き。金額は明細を持たない 0 円
  factory :invoice, class: "Billing::Invoice" do
    owner_tenant_id { Current.tenant_id }
    customer_tenant_id { FactoryBot.create(:tenant).id }
    period_start { Date.current.beginning_of_month }
    period_end { Date.current.end_of_month }
    subtotal { 0 }
    tax_total { 0 }
    total { subtotal + tax_total }

    # 確定済み。採番の規則は確定の公開 API が持つので、番号は乱数で作る
    trait :issued do
      issued_at { Time.current }
      invoice_number { "INV-#{SecureRandom.hex(4)}" }
    end
  end

  factory :invoice_tax_summary, class: "Billing::InvoiceTaxSummary" do
    owner_tenant_id { Current.tenant_id }
    invoice { association :invoice, owner_tenant_id: }
    tax_rate_percent { 10 }
    taxable_amount { 0 }
    tax_amount { 0 }
  end
end
