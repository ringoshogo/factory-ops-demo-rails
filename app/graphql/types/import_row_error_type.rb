module Types
  # 取り込みで失敗した行。取り込みのフィールドとしてだけ現れる
  class ImportRowErrorType < BaseObject
    graphql_name "ImportRowError"
    perspective :supplier
    authorization_exempt reason: "自社の取り込みの行の番号と誤りの文だけを持ち、認可済みの Import のフィールドとしてだけ現れる"

    field :row_number, Int, null: false, description: "見出しを 1 行目とした CSV の行番号"
    field :message, String, null: false, description: "「列名: 理由」の形。行全体の誤りは列名を持たない"
  end
end
