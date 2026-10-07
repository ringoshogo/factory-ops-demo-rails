module Sales
  # 自社の品目の値
  ItemValue = Data.define(:id, :owner_tenant_id, :code, :name, :unit, :unit_price, :tax_rate_percent, :published)
end
