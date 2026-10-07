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
end
