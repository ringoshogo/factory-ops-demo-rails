module Fulfillment
  # 経路 3 で発注側に見せる出荷明細。出荷明細 ID を持たず、連結元の発注明細 ID で識別する
  PartnerShipmentLineValue = Data.define(:supplier_tenant_id, :purchase_order_line_id, :quantity)
end
