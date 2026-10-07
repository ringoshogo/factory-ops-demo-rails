module Types
  # 公開 API が導出した受注の状況（docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）
  class SalesOrderStatusType < BaseEnum
    graphql_name "SalesOrderStatus"

    value "CANCELLED", "取消済", value: :cancelled
    value "INSPECTED", "検収済", value: :inspected
    value "SHIPPED", "出荷済", value: :shipped
    value "AWAITING_PART_MATCH", "品番照合待ち", value: :awaiting_part_match
    value "ALLOCATED", "引当済", value: :allocated
    value "PARTIALLY_ALLOCATED", "一部引当", value: :partially_allocated
    value "RECEIVED", "受注済", value: :received
  end
end
