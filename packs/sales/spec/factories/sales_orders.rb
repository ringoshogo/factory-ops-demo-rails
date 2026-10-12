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
      priced_on { sales_order.order_date }
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

  # 既定は審査中。発注側の取消依頼は ID で参照するだけなので、作らない
  factory :cancellation_review, class: "Sales::CancellationReview" do
    owner_tenant_id { Current.tenant_id }
    sales_order { association :sales_order, owner_tenant_id: }
    source_cancellation_request_id { SecureRandom.uuid }
    requested_at { Time.current }
  end

  # 出荷実績は ID で参照するだけなので、作らない
  factory :inspection_record, class: "Sales::InspectionRecord" do
    owner_tenant_id { Current.tenant_id }
    sales_order_line { association :sales_order_line, owner_tenant_id: }
    shipment_id { SecureRandom.uuid }
    quantity { sales_order_line.quantity }
    inspected_on { Date.current }
  end
end
