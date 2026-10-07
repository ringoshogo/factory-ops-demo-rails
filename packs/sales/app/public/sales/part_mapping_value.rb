module Sales
  # 得意先品番の対応表の 1 行の値
  PartMappingValue = Data.define(:id, :owner_tenant_id, :customer_tenant_id, :customer_part_number, :item_id)
end
