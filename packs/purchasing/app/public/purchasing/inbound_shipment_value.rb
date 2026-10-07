module Purchasing
  # 入荷の値。受注側の出荷実績 ID は持たない（docs/architecture/graphql-schema.md「発注側の視点」）
  InboundShipmentValue = Data.define(:id, :owner_tenant_id, :purchase_order_id, :shipped_on)
end
