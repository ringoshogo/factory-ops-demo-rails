module Fulfillment
  # 読む経路 3。発注側が、自社の発注に連結した出荷を読む（docs/architecture/graphql-schema.md「発注側の視点」）。
  # 有効な取引関係と view_shipments の付与が無ければ空を返す。出荷実績 ID は返さず、連結元の発注で識別する
  module PartnerShipments
    # 発注 ID ごとの出荷。発注 ID は呼ぶ側が自社の発注から渡す。scope が発注側テナントの写しで絞るので、
    # 他社の発注の ID を渡しても何も返らない
    def self.for_purchase_orders(actor, purchase_order_ids)
      shipments = Scope.call(actor, Shipment.where(source_purchase_order_id: purchase_order_ids), name: :partner).order(:id).to_a
      lines = ShipmentLine.where(shipment_id: shipments.map(&:id)).order(:id).group_by(&:shipment_id)
      values = shipments.map do |shipment|
        PartnerShipmentValue.new(supplier_tenant_id: shipment.owner_tenant_id, purchase_order_id: shipment.source_purchase_order_id,
          shipped_on: shipment.shipped_on,
          lines: lines.fetch(shipment.id, []).map do |line|
            PartnerShipmentLineValue.new(supplier_tenant_id: line.owner_tenant_id, purchase_order_line_id: line.source_purchase_order_line_id,
              quantity: line.quantity)
          end)
      end
      purchase_order_ids.index_with { [] }.merge(values.group_by(&:purchase_order_id))
    end
  end
end
