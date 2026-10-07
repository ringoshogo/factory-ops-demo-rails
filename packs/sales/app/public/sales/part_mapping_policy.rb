module Sales
  # 得意先品番の対応表の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。対応表は受注側だけが所有し、相手から読む経路は無い
  class PartMappingPolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    # 一覧と登録は、自社のユーザーなら役割を問わない
    def list? = true

    def register? = true

    def show? = record.owner_tenant_id == user.tenant_id
  end
end
