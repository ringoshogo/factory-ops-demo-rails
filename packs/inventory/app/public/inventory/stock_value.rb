module Inventory
  # 品目ごとの在庫の値。available は有効在庫（on_hand - allocated）で、有効在庫が安全在庫を下回ると below_safety_stock
  StockValue = Data.define(:owner_tenant_id, :item_id, :on_hand, :allocated, :available, :safety_stock, :below_safety_stock)
end
