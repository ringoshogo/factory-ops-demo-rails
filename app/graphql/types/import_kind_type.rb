module Types
  # 取り込みの種類（docs/architecture/data-model.md「取り込み（`imports`）」）。品目は単価の列を含むので、取り込みの開始は admin に限る
  class ImportKindType < BaseEnum
    graphql_name "ImportKind"

    value "ITEMS", "品目と単価", value: "items"
    value "STOCKS", "在庫", value: "stocks"
  end
end
