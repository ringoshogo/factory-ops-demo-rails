module Sales
  # 請求書の単価の説明（docs/adr/006 決定 5）。受注明細が写した単価と有効日と、その有効日の単価を
  # 請求書の発行の時点で信じていた値（発行していなければ空）と、いま信じている値で並べる
  PriceExplanationValue = Data.define(:sales_order_line_id, :ordered_unit_price, :priced_on, :unit_price_as_of_issue, :unit_price_now)
end
