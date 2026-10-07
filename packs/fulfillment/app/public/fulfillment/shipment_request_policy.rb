module Fulfillment
  # 出荷依頼・出荷指示・出荷実績の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。
  # 出荷は受注側だけが所有する。発注側が自社の発注に連結した出荷を読む経路 3 は M14 で足す
  class ShipmentRequestPolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    def list? = true

    # 出荷依頼・明細・出荷指示・出荷実績・出荷明細の値のどれにも使う
    def show? = record.owner_tenant_id == user.tenant_id

    # 出荷指示の作成・取消と出荷の計上は、自社のユーザーなら役割を問わない
    def instruct? = show?
    def ship? = show?
  end
end
