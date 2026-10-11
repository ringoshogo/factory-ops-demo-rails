FactoryBot.define do
  # Tenancy.with_tenant の中で作る
  factory :email_delivery, class: "Notifications::EmailDelivery" do
    owner_tenant_id { Current.tenant_id }
    sequence(:notification_key) { |n| "received_invoice:#{n}" }
    kind { "received_invoice" }
    params { { "invoice_number" => "INV-000001", "issued_on" => "2026-10-12", "total" => "1100" } }
  end
end
