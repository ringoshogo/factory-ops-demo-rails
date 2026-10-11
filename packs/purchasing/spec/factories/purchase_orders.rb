FactoryBot.define do
  # どれも Tenancy.with_tenant の中で、発注側のテナントで作る
  factory :purchase_order, class: "Purchasing::PurchaseOrder" do
    owner_tenant_id { Current.tenant_id }
    sequence(:order_no) { |n| format("PO-F%05d", n) }
    supplier_tenant_id { FactoryBot.create(:tenant).id }
    order_date { Date.current }
  end

  factory :purchase_order_line, class: "Purchasing::PurchaseOrderLine" do
    owner_tenant_id { Current.tenant_id }
    purchase_order { association :purchase_order, owner_tenant_id: }
    sequence(:part_number) { |n| "PART-#{n}" }
    quantity { 1 }
  end

  factory :purchase_order_sequence, class: "Purchasing::PurchaseOrderSequence" do
    owner_tenant_id { Current.tenant_id }
  end

  # 受注側の出荷実績は ID で参照するだけなので、作らない
  factory :inbound_shipment, class: "Purchasing::InboundShipment" do
    owner_tenant_id { Current.tenant_id }
    purchase_order { association :purchase_order, owner_tenant_id: }
    shipment_id { SecureRandom.uuid }
    shipped_on { Date.current }
  end

  factory :inbound_shipment_line, class: "Purchasing::InboundShipmentLine" do
    owner_tenant_id { Current.tenant_id }
    inbound_shipment { association :inbound_shipment, owner_tenant_id: }
    purchase_order_line { association :purchase_order_line, owner_tenant_id:, purchase_order: inbound_shipment.purchase_order }
    shipped_quantity { purchase_order_line.quantity }
  end

  factory :receipt_inspection, class: "Purchasing::ReceiptInspection" do
    owner_tenant_id { Current.tenant_id }
    inbound_shipment { association :inbound_shipment, owner_tenant_id: }
    inspected_on { Date.current }
  end

  # 検収の入荷の明細を検収する
  factory :receipt_inspection_line, class: "Purchasing::ReceiptInspectionLine" do
    owner_tenant_id { Current.tenant_id }
    receipt_inspection { association :receipt_inspection, owner_tenant_id: }
    inbound_shipment_line { association :inbound_shipment_line, owner_tenant_id:, inbound_shipment: receipt_inspection.inbound_shipment }
    accepted_quantity { inbound_shipment_line.shipped_quantity }
  end

  # 既定は回答待ち
  factory :cancellation_request, class: "Purchasing::CancellationRequest" do
    owner_tenant_id { Current.tenant_id }
    purchase_order { association :purchase_order, owner_tenant_id: }
    reason { "数量の誤り" }
  end

  # 受注側の請求書は ID で参照するだけなので、作らない
  factory :received_invoice, class: "Purchasing::ReceivedInvoice" do
    owner_tenant_id { Current.tenant_id }
    invoice_id { SecureRandom.uuid }
    supplier_tenant_id { FactoryBot.create(:tenant).id }
    invoice_number { "INV-#{SecureRandom.hex(4)}" }
    period_start { Date.current.beginning_of_month }
    period_end { Date.current.end_of_month }
    issued_on { Date.current }
    subtotal { 0 }
    tax_total { 0 }
    total { subtotal + tax_total }
  end

  factory :received_invoice_line, class: "Purchasing::ReceivedInvoiceLine" do
    owner_tenant_id { Current.tenant_id }
    received_invoice { association :received_invoice, owner_tenant_id: }
    purchase_order_line { association :purchase_order_line, owner_tenant_id: }
    item_name { "六角ボルト M8" }
    unit_price { 120 }
    quantity { 1 }
    tax_rate_percent { 10 }
    amount { unit_price * quantity }
  end
end
