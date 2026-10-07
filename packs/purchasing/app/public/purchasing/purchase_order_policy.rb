module Purchasing
  # 発注の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。発注は発注側だけが所有し、相手から読む経路は無い
  class PurchaseOrderPolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    # 一覧と発注の登録は、自社のユーザーなら役割を問わない。相手への place_orders は Ordering.place が確かめる
    def list? = true

    def place? = true

    # 発注と発注明細の値のどちらにも使う
    def show? = record.owner_tenant_id == user.tenant_id
  end
end
