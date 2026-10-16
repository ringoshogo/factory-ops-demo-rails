module Fulfillment
  # 出荷依頼・出荷指示・出荷実績の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。
  # 出荷は受注側だけが所有する。scope は所有の条件を明示し、RLS に任せない。RLS は経路 3 の相手の出荷も返すからである
  class ShipmentRequestPolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    # 経路 3：自社が発注側の出荷のうち、有効な取引関係と view_shipments の付与がある受注側のものだけ。
    # 受注側は取引関係の公開 API の副問い合わせで絞り、取引関係の列の名前を書かない
    relation_scope(:partner) do |relation|
      suppliers = Partnerships::Access.permitting_suppliers_sql(user, permission: :view_shipments)
      relation.where(buyer_tenant_id: user.tenant_id).where(suppliers.contains(:tenant_id, relation.arel_table[:owner_tenant_id]))
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

      # 出荷と明細ごとに評価しても、問い合わせは 1 回の実行で 1 回で済ませる。
      # 受注側ごとに問い合わせると、発注の一覧の相手が多いほどクエリが増える
      permitting = remember(:view_shipments_suppliers) do
        Partnerships::Access.permitting_supplier_ids(user, permission: :view_shipments)
      end
      permitting.include?(record.supplier_tenant_id)
    end
  end
end
