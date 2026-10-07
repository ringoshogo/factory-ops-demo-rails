module Fulfillment
  # 経路 3 で発注側に見せる出荷。出荷実績 ID を持たず、受注側テナントと連結元の発注 ID で識別する
  PartnerShipmentValue = Data.define(:supplier_tenant_id, :purchase_order_id, :shipped_on, :lines)
end
