module Sales
  # 受注明細の値。連結元の発注明細 ID は相手側を指すので持たない。照合前は item_id と写しが空
  SalesOrderLineValue = Data.define(:id, :owner_tenant_id, :sales_order_id, :customer_part_number, :item_id, :item_name,
    :unit_price, :tax_rate_percent, :quantity, :allocated_quantity)
end
