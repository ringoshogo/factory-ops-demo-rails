# 入口の行列の期待値。視点の入口と Mutation のフィールドはすべてここに行を持つ。
# 行の無いフィールドがあれば spec/matrix/graphql_matrix_spec.rb が落ちる
module MatrixExpectations
  # 値が返る・空の一覧・null・ユーザーエラーの NOT_FOUND と NOT_PERMITTED・トップレベルのエラーの FORBIDDEN
  # （docs/architecture/graphql-schema.md「エラー」）
  OUTCOMES = %i[value empty null not_found not_permitted forbidden].freeze

  # "型.フィールド" => { query:, variables: ->(world) { ... }（省略可）, expect: { ペルソナ => 結果 } }。
  # query は対象のフィールドを 1 つだけ選ぶ。variables は世界の行の ID を引数に渡すときに書く
  GRAPHQL = {
    "Query.viewer" => {
      query: "{ viewer { id } }",
      expect: { supplier: :value, stranger: :value }
    }
  }.freeze
end
