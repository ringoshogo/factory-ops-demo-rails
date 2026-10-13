module Types
  # 品目の一覧の並べ替えの列。一覧の表の列と、その列から計算する値に限る（docs/architecture/graphql-schema.md「ページングと N+1」）
  class ItemOrderFieldType < BaseEnum
    graphql_name "ItemOrderField"

    value "CODE", "品目コード", value: :code
    value "NAME", "品目名", value: :name
  end
end
