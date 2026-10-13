module Types
  # 在庫の一覧の並べ替えの列。品目のコードと名前は、在庫のコンテキストに写した品目の写しで並べる
  # （docs/architecture/graphql-schema.md「ページングと N+1」）
  class StockOrderFieldType < BaseEnum
    graphql_name "StockOrderField"

    value "ON_HAND", "現在庫", value: :on_hand
    value "ALLOCATED", "引当", value: :allocated
    value "AVAILABLE", "有効在庫（現在庫 - 引当）", value: :available
    value "SAFETY_STOCK", "安全在庫", value: :safety_stock
    value "ITEM_CODE", "品目コード。品目の写しの無い在庫は、向きによらず最後に並ぶ", value: :item_code
    value "ITEM_NAME", "品目名。品目の写しの無い在庫は、向きによらず最後に並ぶ", value: :item_name
  end
end
