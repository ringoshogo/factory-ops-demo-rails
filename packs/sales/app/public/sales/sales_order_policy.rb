module Sales
  # 受注の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。受注は受注側だけが所有し、相手から読む経路は無い
  class SalesOrderPolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    def list? = true

    # 受注と受注明細の値のどちらにも使う
    def show? = record.owner_tenant_id == user.tenant_id
  end
end
