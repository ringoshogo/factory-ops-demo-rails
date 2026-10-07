FactoryBot.define do
  # Tenancy.with_tenant の中で作る
  factory :item, class: "Sales::Item" do
    owner_tenant_id { Current.tenant_id }
    sequence(:code) { |n| "ITEM-#{n}" }
    name { "六角ボルト M8" }
    unit { "個" }
    unit_price { 120 }

    trait :published do
      published { true }
    end
  end
end
