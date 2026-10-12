module Purchasing
  # 発注と受領請求書の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。どちらも発注側だけが所有し、相手から読む経路は無い
  class PurchaseOrderPolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    # 一覧と発注の登録は、自社のユーザーなら役割を問わない。相手への place_orders は Ordering.place が確かめる
    def list? = true

    def place? = true

    # 取消依頼は取引を取り消す操作、入荷の検収は金額を確定させる操作なので admin に限る
    # （docs/architecture/context-map.md「自社の中の役割」）
    def request_cancellation? = user.admin? && show?
    def inspect_receipt? = user.admin? && show?

    # 発注・発注明細・入荷・検収・受領請求書の値のどれにも使う
    def show? = record.owner_tenant_id == user.tenant_id
  end
end
