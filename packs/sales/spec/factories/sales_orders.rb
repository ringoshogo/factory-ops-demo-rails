FactoryBot.define do
  # どれも Tenancy.with_tenant の中で、受注側のテナントで作る
  factory :sales_order, class: "Sales::SalesOrder" do
    owner_tenant_id { Current.tenant_id }
    sequence(:order_no) { |n| format("SO-F%05d", n) }
    customer_tenant_id { FactoryBot.create(:tenant).id }
    source_purchase_order_id { SecureRandom.uuid }
    order_date { Date.current }
  end

  # 既定は照合前の明細
  factory :sales_order_line, class: "Sales::SalesOrderLine" do
    owner_tenant_id { Current.tenant_id }
    sales_order { association :sales_order, owner_tenant_id: }
    source_purchase_order_line_id { SecureRandom.uuid }
    sequence(:customer_part_number) { |n| "PART-#{n}" }
    quantity { 1 }

    trait :matched do
      item_id { FactoryBot.create(:item, owner_tenant_id:).id }
      item_name { "六角ボルト M8" }
      unit_price { 120 }
      tax_rate_percent { 10 }
    end
  end

  factory :sales_order_sequence, class: "Sales::SalesOrderSequence" do
    owner_tenant_id { Current.tenant_id }
  end

  factory :customer_part_mapping, class: "Sales::CustomerPartMapping" do
    owner_tenant_id { Current.tenant_id }
    customer_tenant_id { FactoryBot.create(:tenant).id }
    sequence(:customer_part_number) { |n| "PART-#{n}" }
    item { association :item, owner_tenant_id: }
  end
end
