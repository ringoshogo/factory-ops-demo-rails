FactoryBot.define do
  # Tenancy.with_tenant の中で作る
  factory :user, class: "Partnerships::User" do
    owner_tenant_id { Current.tenant_id }
    sequence(:email) { |n| "user#{n}@example.com" }
    name { "利用者" }
    role { "member" }
    password { "password" }

    trait :admin do
      role { "admin" }
    end
  end
end
