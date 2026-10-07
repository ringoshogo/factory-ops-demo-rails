module Fulfillment
  # 出荷依頼・出荷指示・出荷実績の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。
  # 出荷は受注側だけが所有する。scope は所有の条件を明示し、RLS に任せない。RLS は経路 3 の相手の出荷も返すからである
  class ShipmentRequestPolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    # 経路 3：自社が発注側の出荷のうち、有効な取引関係と view_shipments の付与がある受注側のものだけ
    relation_scope(:partner) do |relation|
      relation.where(buyer_tenant_id: user.tenant_id,
        owner_tenant_id: Partnerships::Access.permitting_suppliers(user, permission: :view_shipments))
    end

    def list? = true

    # 出荷依頼・明細・出荷指示・出荷実績・出荷明細の値のどれにも使う
    def show? = record.owner_tenant_id == user.tenant_id

    # 出荷指示の作成・取消と出荷の計上は、自社のユーザーなら役割を問わない
    def instruct? = show?
    def ship? = show?

    # 経路 3 の出荷と出荷明細の値
    def show_to_buyer?
      return false unless record.is_a?(PartnerShipmentValue) || record.is_a?(PartnerShipmentLineValue)

      # 出荷と明細ごとに評価しても、問い合わせは受注側ごとに 1 回で済ませる
      remember([ :view_shipments, record.supplier_tenant_id ]) do
        Partnerships::Access.permitted?(user, supplier_tenant_id: record.supplier_tenant_id, permission: :view_shipments)
      end
    end
  end
end
