module Types
  # 取消依頼の回答と、取消の審査の決着。空は回答待ち・審査中（docs/architecture/graphql-schema.md「状況の enum」）
  class CancellationOutcomeType < BaseEnum
    graphql_name "CancellationOutcome"

    value "APPROVED", "承認", value: :approved
    value "REJECTED", "却下", value: :rejected
  end
end
