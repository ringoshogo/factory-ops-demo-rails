module Types
  # 在庫の一覧の絞り込み
  class StockFilterType < BaseInputObject
    graphql_name "StockFilter"

    argument :below_safety_stock, Boolean, required: false,
      description: "真なら、ダッシュボードの stocksBelowSafetyStock と同じ条件（有効在庫が安全在庫より小さい）で絞る。偽か省けば絞らない"
  end
end
