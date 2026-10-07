FactoryBot.define do
  # Tenancy.with_tenant の中で、受注側のテナントで作る
  factory :partnership, class: "Partnerships::Partnership" do
    owner_tenant_id { Current.tenant_id }
    buyer_tenant_id { FactoryBot.create(:tenant).id }

    transient do
      permissions { [] }
    end

    after(:create) do |partnership, evaluator|
      evaluator.permissions.each do |permission|
        partnership.grants.create!(owner_tenant_id: partnership.owner_tenant_id, permission:)
      end
    end

    trait :revoked do
      status { "revoked" }
      revoked_at { Time.current }
    end
  end
end
