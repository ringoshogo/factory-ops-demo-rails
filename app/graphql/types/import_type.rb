module Types
  # 受注側が自社の CSV を取り込んだ記録。件数はチャンクを反映するたびに進む
  class ImportType < BaseObject
    graphql_name "Import"
    perspective :supplier
    authorize_with Imports::ImportPolicy

    field :id, ID, null: false
    field :kind, ImportKindType, null: false
    field :status, ImportStatusType, null: false
    field :total_rows, Int, description: "見出しを除いた行の数。置き場へ写し終えるまで空"
    field :applied_rows, Int, null: false
    field :failed_rows, Int, null: false
    field :started_at, GraphQL::Types::ISO8601DateTime
    field :finished_at, GraphQL::Types::ISO8601DateTime
    field :row_errors, resolver: Resolvers::Supplier::ImportRowErrorsResolver, description: "失敗した行。行番号の順"
  end
end
