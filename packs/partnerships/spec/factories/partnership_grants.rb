FactoryBot.define do
  # Tenancy.with_tenant の中で作る
  factory :partnership_grant, class: "Partnerships::PartnershipGrant" do
    owner_tenant_id { Current.tenant_id }
    partnership { association :partnership, owner_tenant_id: }
    permission { "view_catalog" }
  end
end
