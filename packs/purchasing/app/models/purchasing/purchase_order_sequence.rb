module Purchasing
  # 発注番号の採番行。テナントごとに 1 行（DocumentNumber）
  class PurchaseOrderSequence < TenantRecord
  end
end
