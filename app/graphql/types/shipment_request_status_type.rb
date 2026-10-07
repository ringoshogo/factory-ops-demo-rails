module Types
  # 公開 API が導出した出荷依頼の状況（docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
  # 「出荷停止中」（ON_HOLD）は M15 で足す
  class ShipmentRequestStatusType < BaseEnum
    graphql_name "ShipmentRequestStatus"

    value "CANCELLED", "取消済", value: :cancelled
    value "SHIPPED", "出荷済", value: :shipped
    value "INSTRUCTED", "出荷指示済", value: :instructed
    value "READY", "出荷待ち", value: :ready
  end
end
