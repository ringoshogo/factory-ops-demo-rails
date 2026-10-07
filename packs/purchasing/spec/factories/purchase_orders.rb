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
end
