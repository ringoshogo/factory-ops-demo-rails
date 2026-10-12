module Types
  # 出荷依頼の一覧の並べ替えの列。一覧の表の列と、その列から計算する値に限る（docs/architecture/graphql-schema.md「ページングと N+1」）
  class ShipmentRequestOrderFieldType < BaseEnum
    graphql_name "ShipmentRequestOrderField"

    value "DUE_DATE", "出荷期限", value: :due_date
  end
end
