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

    # 同じテナントの在庫の写しも書く。在庫の調整と在庫数の設定は、写しの無い品目を拒む（Inventory::Adjustment）。
    # 既定で写しを作らないのは、写しの無い品目に写しを足す作り直しの spec が、写しの無い品目を前提にするからである
    trait :labeled do
      after(:create) { |item| Inventory::ItemLabels.put([ { item_id: item.id, code: item.code, name: item.name } ]) }
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
