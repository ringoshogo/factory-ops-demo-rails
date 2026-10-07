module Sales
  # 受注明細。照合前は item_id と写しの 3 列（item_name・unit_price・tax_rate_percent）が空
  class SalesOrderLine < TenantRecord
    belongs_to :sales_order, inverse_of: :lines

    def matched? = item_id.present?
  end
end
