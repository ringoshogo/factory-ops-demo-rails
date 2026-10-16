module Types
  # 発注の進みの出来事。発注側が持つ自社の行から組み立て、受注側の内部の進み（引当・出荷指示）は出さない
  class PurchaseOrderTimelineEntryType < BaseObject
    graphql_name "PurchaseOrderTimelineEntry"
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy

    field :kind, PurchaseOrderTimelineKindType, null: false
    field :occurred_on, GraphQL::Types::ISO8601Date, null: false, description: "日本時間の日付"
    field :occurred_at, GraphQL::Types::ISO8601DateTime, description: "時刻。日付だけの出来事（出荷・検収・請求書の受領）は空"
  end
end
