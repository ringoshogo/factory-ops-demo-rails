module Sales
  # 販売単価の 1 行の値。valid_from は含み valid_to は含まず、recorded_to までの記録期間に正しいと信じていた。
  # valid_from・valid_to・recorded_to の空は、その向きに上限が無いことを表す
  ItemPriceValue = Data.define(:id, :owner_tenant_id, :item_id, :unit_price, :valid_from, :valid_to, :recorded_from, :recorded_to,
    :reason)
end
