module Inventory
  # 在庫移動履歴の値。type は inbound・outbound・allocate・deallocate・ship。引当の ID は持たない
  StockMovementValue = Data.define(:id, :owner_tenant_id, :item_id, :type, :quantity, :reason, :created_at)
end
