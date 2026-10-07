module Purchasing
  # 発注明細の値。confirmed_* は「受注確定」で写した値で、確定前は空
  PurchaseOrderLineValue = Data.define(:id, :owner_tenant_id, :purchase_order_id, :part_number, :quantity,
    :confirmed_item_name, :confirmed_unit_price)
end
