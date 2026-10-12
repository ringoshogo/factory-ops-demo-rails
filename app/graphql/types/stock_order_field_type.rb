module Types
  # 在庫の一覧の並べ替えの列。一覧の表の列と、その列から計算する値に限る（docs/architecture/graphql-schema.md「ページングと N+1」）
  class StockOrderFieldType < BaseEnum
    graphql_name "StockOrderField"

    value "ON_HAND", "現在庫", value: :on_hand
    value "ALLOCATED", "引当", value: :allocated
    value "AVAILABLE", "有効在庫（現在庫 - 引当）", value: :available
    value "SAFETY_STOCK", "安全在庫", value: :safety_stock
  end
end
