FactoryBot.define do
  # Tenancy.with_tenant の中で作る。競合テストが残したユーザーとメールアドレスで衝突しないよう、乱数で作る
  # （docs/guides/testing.md「競合テスト」）
  factory :user, class: "Partnerships::User" do
    owner_tenant_id { Current.tenant_id }
    email { "user-#{SecureRandom.hex(8)}@example.com" }
    name { "利用者" }
    role { "member" }
    password { "password" }

    trait :admin do
      role { "admin" }
    end
  end
end
