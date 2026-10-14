module Types
  # 発注の一覧の並べ替えの列。一覧の表の列と、その列から計算する値と、取引先の名前（docs/architecture/graphql-schema.md「ページングと N+1」）
  class PurchaseOrderOrderFieldType < BaseEnum
    graphql_name "PurchaseOrderOrderField"

    value "ORDER_NO", "発注番号", value: :order_no
    value "ORDER_DATE", "発注日", value: :order_date
    value "DESIRED_DELIVERY_ON", "希望納期", value: :desired_delivery_on
    value "SUPPLIER_NAME", "受注側の名前", value: :supplier_name
    value "TOTAL_AMOUNT", "合計金額。受注確定の前の明細を含む発注は向きによらず最後", value: :total_amount
    value "STATUS", "状況。業務の進み順", value: :status
  end
end
