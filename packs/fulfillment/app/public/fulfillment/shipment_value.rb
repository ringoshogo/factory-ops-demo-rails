module Fulfillment
  # 出荷実績の値。発注側テナントと連結元の発注 ID の写しは持たない
  ShipmentValue = Data.define(:id, :owner_tenant_id, :shipment_request_id, :shipped_on)
end
