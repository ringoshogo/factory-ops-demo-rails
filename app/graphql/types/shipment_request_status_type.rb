module Types
  # 公開 API が導出した出荷依頼の状況（docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
  # 出荷停止を記録する表（shipping_holds）が無く、導出表の「出荷停止中」は導出しないので、値に置かない
  class ShipmentRequestStatusType < BaseEnum
    graphql_name "ShipmentRequestStatus"

    value "CANCELLED", "取消済", value: :cancelled
    value "SHIPPED", "出荷済", value: :shipped
    value "INSTRUCTED", "出荷指示済", value: :instructed
    value "READY", "出荷待ち", value: :ready
  end
end
