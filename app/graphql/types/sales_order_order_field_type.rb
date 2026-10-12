module Types
  # 受注の一覧の並べ替えの列。一覧の表の列と、その列から計算する値に限る（docs/architecture/graphql-schema.md「ページングと N+1」）
  class SalesOrderOrderFieldType < BaseEnum
    graphql_name "SalesOrderOrderField"

    value "ORDER_NO", "受注番号", value: :order_no
    value "ORDER_DATE", "受注日", value: :order_date
    value "DUE_DATE", "希望納期", value: :due_date
  end
end
