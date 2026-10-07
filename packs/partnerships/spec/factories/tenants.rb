FactoryBot.define do
  # tenants は RLS を付けない表なので、テナントを設定せずに作れる
  factory :tenant, class: "Partnerships::Tenant" do
    sequence(:code) { |n| "tenant-#{n}" }
    name { code }
    partner_code { SecureRandom.hex(16) }
  end
end
