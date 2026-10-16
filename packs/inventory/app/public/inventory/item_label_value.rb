module Inventory
  # 自社の品目の写しの値。在庫の調整の対象の品目で、規則（StockPolicy#adjust?）は owner_tenant_id を読む
  ItemLabelValue = Data.define(:owner_tenant_id, :item_id, :code, :name)
end
