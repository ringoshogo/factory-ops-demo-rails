module Types
  # 発注の一覧の並べ替えの列。一覧の表の列と、その列から計算する値に限る（docs/architecture/graphql-schema.md「ページングと N+1」）
  class PurchaseOrderOrderFieldType < BaseEnum
    graphql_name "PurchaseOrderOrderField"

    value "ORDER_NO", "発注番号", value: :order_no
    value "ORDER_DATE", "発注日", value: :order_date
    value "DESIRED_DELIVERY_ON", "希望納期", value: :desired_delivery_on
  end
end
