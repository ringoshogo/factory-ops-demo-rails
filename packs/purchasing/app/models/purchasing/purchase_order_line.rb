module Purchasing
  # 発注明細。part_number は発注側の自社品番。confirmed_* は「受注確定」で写した値で、確定前は空
  class PurchaseOrderLine < TenantRecord
    belongs_to :purchase_order, inverse_of: :lines
  end
end
