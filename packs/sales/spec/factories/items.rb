FactoryBot.define do
  # Tenancy.with_tenant の中で作る。品目を作ると、unit_price を有効期間 (,) の単価の行として足す（Sales::Catalog.save と同じ形）。
  # unit_price: nil は単価の行の無い品目を作る
  factory :item, class: "Sales::Item" do
    owner_tenant_id { Current.tenant_id }
    sequence(:code) { |n| "ITEM-#{n}" }
    name { "六角ボルト M8" }
    unit { "個" }

    transient do
      unit_price { 120 }
    end

    after(:create) do |item, context|
      FactoryBot.create(:item_price, item:, unit_price: context.unit_price) unless context.unit_price.nil?
    end

    trait :published do
      published { true }
    end
  end

  # 既定は、単価の行の無い品目の、有効期間 (,) の現在の行
  factory :item_price, class: "Sales::ItemPrice" do
    owner_tenant_id { Current.tenant_id }
    item { association :item, owner_tenant_id:, unit_price: nil }
    unit_price { 120 }
    valid_period { nil...nil }
    recorded_period { Time.current... }
  end
end
