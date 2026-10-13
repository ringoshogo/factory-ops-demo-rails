module Types
  # 品目の一覧の絞り込み
  class ItemFilterType < BaseInputObject
    graphql_name "ItemFilter"

    # 長い値で品目の表を部分一致で走査させないよう、SQL を流す前に引数の誤りにする
    argument :keyword, String, required: false, validates: { length: { maximum: Keyword::MAX_LENGTH } },
      description: "前後の空白を除いて、品目コードか品目名に含む品目に絞る。大文字と小文字を区別せず、% と _ は文字として扱う。空なら絞らない。100 文字まで"
  end
end
