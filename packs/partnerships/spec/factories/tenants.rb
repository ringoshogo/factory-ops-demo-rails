FactoryBot.define do
  # tenants は RLS を付けない表なので、テナントを設定せずに作れる。
  # 競合テストが残したテナントと一意の値で衝突しないよう、一意の値は乱数で作る（docs/guides/testing.md「競合テスト」）
  factory :tenant, class: "Partnerships::Tenant" do
    code { "tenant-#{SecureRandom.hex(8)}" }
    name { code }
    partner_code { SecureRandom.hex(16) }
  end
end
