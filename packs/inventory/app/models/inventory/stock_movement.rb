module Inventory
  # 在庫移動履歴。追記だけで、書いた行は変えない。増減の向きは type が決める
  class StockMovement < TenantRecord
    self.inheritance_column = nil

    belongs_to :allocation, class_name: "Inventory::StockAllocation", optional: true

    def readonly? = persisted? || super
  end
end
