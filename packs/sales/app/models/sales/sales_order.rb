module Sales
  # 受注。customer_tenant_id・source_purchase_order_id は相手テナントの ID 参照で、関連を張らない
  class SalesOrder < TenantRecord
    has_many :lines, -> { order(:id) }, class_name: "Sales::SalesOrderLine", inverse_of: :sales_order
  end
end
