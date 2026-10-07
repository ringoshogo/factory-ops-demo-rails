module Partnerships
  # 取引関係の可視範囲と規則（docs/architecture/graphql-schema.md「認可」「役割による制限」）。
  # scope は所有の条件を明示し、RLS に任せない。RLS は経路 2 の相手の行も返すからである
  class PartnershipPolicy < ApplicationPolicy
    # 自社が受注側の関係。失効したものも含む
    relation_scope(:as_supplier) { |relation| relation.where(owner_tenant_id: user.tenant_id) }
    # 経路 2：自社が発注側の、有効な関係だけ
    relation_scope(:as_buyer) { |relation| relation.active.where(buyer_tenant_id: user.tenant_id) }

    # 一覧は自社のユーザーなら役割を問わない
    def list? = true

    def show? = record.supplier.id == user.tenant_id

    def show_to_buyer? = record.buyer.id == user.tenant_id && record.status == "active"

    # 取引関係と権限付与を変えるのは受注側の admin だけ。結ぶ操作は対象が無いので操作者に対して評価する
    def establish? = user.admin?

    def manage? = user.admin? && show?
  end
end
