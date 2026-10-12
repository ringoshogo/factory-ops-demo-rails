module Imports
  # 取り込みの CSV の見出し。種類ごとに、列名をこの順で 1 行目に並べる（docs/architecture/data-model.md「取り込み（`imports`）」）
  module CsvFormat
    COLUMNS = {
      "items" => %w[code name unit tax_rate_percent published unit_price price_effective_on],
      "stocks" => %w[item_code quantity]
    }.freeze
  end
end
