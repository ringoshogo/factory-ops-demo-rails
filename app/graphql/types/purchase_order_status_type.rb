module Types
  # 公開 API が導出した発注の状況（docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）
  class PurchaseOrderStatusType < BaseEnum
    graphql_name "PurchaseOrderStatus"

    value "SUPPLIER_CANCELLED", "受注側により取消", value: :supplier_cancelled
    value "CANCELLED", "取消済み", value: :cancelled
    value "INSPECTED", "検収済", value: :inspected
    value "INBOUND", "入荷予定", value: :inbound
    value "ACCEPTED", "受注済", value: :accepted
    value "AWAITING_SUPPLIER_CONFIRMATION", "受注側で確認中", value: :awaiting_supplier_confirmation
    value "SENT", "送信済み", value: :sent
  end
end
