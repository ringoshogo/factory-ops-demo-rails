module Types
  # 受注の一覧の並べ替えの列。一覧の表の列と、その列から計算する値と、取引先の名前（docs/architecture/graphql-schema.md「ページングと N+1」）
  class SalesOrderOrderFieldType < BaseEnum
    graphql_name "SalesOrderOrderField"

    value "ORDER_NO", "受注番号", value: :order_no
    value "ORDER_DATE", "受注日", value: :order_date
    value "DUE_DATE", "希望納期", value: :due_date
    value "CUSTOMER_NAME", "得意先の名前", value: :customer_name
    value "TOTAL_AMOUNT", "合計金額。単価の無い明細を含む受注は向きによらず最後", value: :total_amount
    value "STATUS", "状況。業務の進み順", value: :status
  end
end
