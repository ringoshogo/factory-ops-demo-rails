module Inventory
  # 在庫・引当・移動履歴の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。在庫は受注側だけが所有し、相手から読む経路は無い
  class StockPolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    # 一覧と入出庫の調整は、自社のユーザーなら役割を問わない
    def list? = true

    # 在庫と移動履歴の値のどちらにも使う
    def show? = record.owner_tenant_id == user.tenant_id

    # 対象は調整する品目の値
    def adjust? = show?
  end
end
