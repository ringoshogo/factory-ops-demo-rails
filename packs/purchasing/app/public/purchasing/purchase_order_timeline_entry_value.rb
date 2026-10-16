module Purchasing
  # 発注の進みの出来事の値（docs/architecture/graphql-schema.md「発注側の視点」）。occurred_on は日本時間の日付で、
  # occurred_at は時刻の列から読んだ出来事だけが持ち、日付の列から読んだ出来事（出荷・検収・請求書の受領）では空。
  # owner_tenant_id は型の認可が読むために持ち、GraphQL のフィールドには出さない
  PurchaseOrderTimelineEntryValue = Data.define(:kind, :occurred_on, :occurred_at, :owner_tenant_id)
end
