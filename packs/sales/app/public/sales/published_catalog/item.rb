module Sales
  module PublishedCatalog
    # 取引先に見せる公開品目。相手テナントの内部の ID を持たず、受注側テナントと品目コードで識別する
    Item = Data.define(:supplier_tenant_id, :code, :name, :unit, :unit_price, :tax_rate_percent)
  end
end
