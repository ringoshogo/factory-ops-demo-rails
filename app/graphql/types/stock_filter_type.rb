module Types
  # 在庫の一覧の絞り込み
  class StockFilterType < BaseInputObject
    graphql_name "StockFilter"

    argument :below_safety_stock, Boolean, required: false,
      description: "真なら、ダッシュボードの stocksBelowSafetyStock と同じ条件（有効在庫が安全在庫より小さい）で絞る。偽か省けば絞らない"
    # 規則と上限は品目の一覧の keyword（ItemFilter）と同じ
    argument :keyword, String, required: false, validates: { length: { maximum: Keyword::MAX_LENGTH } },
      description: "前後の空白を除いて、品目コードか品目名に含む品目の在庫に絞る。大文字と小文字を区別せず、% と _ は文字として扱う。空なら絞らない。#{Keyword::MAX_LENGTH} 文字まで"
  end
end
