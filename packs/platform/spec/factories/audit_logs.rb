FactoryBot.define do
  # Tenancy.with_tenant の中で作る。基底クラスが書く行と同じく、利用者の操作の行にする
  factory :audit_log, class: "AuditLog" do
    owner_tenant_id { Current.tenant_id }
    actor_type { "user" }
    actor_user_id { SecureRandom.uuid }
    action { "item.save" }
    target_type { "Item" }
    target_id { SecureRandom.uuid }
    correlation_id { SecureRandom.uuid }
  end
end
