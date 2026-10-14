module Types
  # 出荷依頼の一覧の並べ替えの列。一覧の表の列と、その列から計算する値と、取引先の名前と、受注番号の写しと、
  # 有効な出荷指示の出荷予定日（docs/architecture/graphql-schema.md「ページングと N+1」）
  class ShipmentRequestOrderFieldType < BaseEnum
    graphql_name "ShipmentRequestOrderField"

    value "DUE_DATE", "出荷期限", value: :due_date
    value "CUSTOMER_NAME", "得意先の名前", value: :customer_name
    value "STATUS", "状況。業務の進み順", value: :status
    value "ORDER_NO", "受注番号", value: :order_no
    value "PLANNED_DATE", "有効な出荷指示の出荷予定日。指示の無い出荷依頼は空", value: :planned_date
  end
end
