module Types
  # 発注の進みの出来事の種類。業務の順に並べる（docs/architecture/graphql-schema.md「発注側の視点」）
  class PurchaseOrderTimelineKindType < BaseEnum
    graphql_name "PurchaseOrderTimelineKind"

    value "ORDERED", "発注登録", value: :ordered
    value "PART_MATCH_PENDING", "品番照合待ち", value: :part_match_pending
    value "ACCEPTED", "受注確定", value: :accepted
    value "CANCELLATION_REQUESTED", "取消依頼", value: :cancellation_requested
    value "CANCELLATION_APPROVED", "取消の承認", value: :cancellation_approved
    value "CANCELLATION_REJECTED", "取消の却下", value: :cancellation_rejected
    value "SUPPLIER_CANCELLED", "受注側の取消", value: :supplier_cancelled
    value "SHIPPED", "出荷", value: :shipped
    value "INSPECTED", "検収", value: :inspected
    value "INVOICE_RECEIVED", "請求書の受領", value: :invoice_received
  end
end
