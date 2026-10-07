module Sales
  # 受注の値。連結元の発注 ID は相手側を指すので持たない。status は SalesOrderStatus が導出した記号
  SalesOrderValue = Data.define(:id, :owner_tenant_id, :order_no, :customer_tenant_id, :order_date, :due_date, :status)
end
