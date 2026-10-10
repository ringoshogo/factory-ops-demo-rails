module Platform
  # 監査ログの可視範囲と規則（docs/architecture/graphql-schema.md「監査ログ」）。読めるのは自社の admin だけで、
  # 相手テナントの受信の行は相手のものなので見えない
  class AuditLogPolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    def index? = user.admin?

    def show? = record.owner_tenant_id == user.tenant_id
  end
end
