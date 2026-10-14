module Types
  # 品目の一覧の並べ替えの列。一覧の表の列と、今日の単価と、在庫の安全在庫（docs/architecture/graphql-schema.md「ページングと N+1」）
  class ItemOrderFieldType < BaseEnum
    graphql_name "ItemOrderField"

    value "CODE", "品目コード", value: :code
    value "NAME", "品目名", value: :name
    value "UNIT", "単位", value: :unit
    value "UNIT_PRICE", "今日の販売単価", value: :unit_price
    value "SAFETY_STOCK", "安全在庫。在庫の行の無い品目は空", value: :safety_stock
  end
end
