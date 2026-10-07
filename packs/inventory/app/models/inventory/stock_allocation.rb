module Inventory
  # 受注明細ごとの引当。公開 API の Inventory::Allocation と名前が重なるので、モデルはこの名前にする。
  # sales_order_line_id は受注の行の ID 参照で、関連を張らない
  class StockAllocation < TenantRecord
    self.table_name = "allocations"

    STATUSES = %w[active released consumed].freeze

    validates :status, inclusion: { in: STATUSES }

    def active? = status == "active"
    def consumed? = status == "consumed"
  end
end
