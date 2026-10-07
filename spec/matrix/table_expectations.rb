# 表の行列の期待値。テナントの表はすべてここに行を持つ。行の無い表があれば spec/matrix/table_matrix_spec.rb が落ちる。
# 書き込みに期待値は無い。どの表も、相手の名義で書けず、相手の行を変えられない
module MatrixExpectations
  OWNER_ONLY = {}.freeze

  # 表 => { 読むペルソナ => { 所有者のペルソナ => 見える件数 } }。自社の行は常に読めるので書かない。
  # 所有者以外に見せるのは読む 3 経路の表だけ（docs/architecture/context-map.md「テナントと所有」）
  TABLES = {
    "users" => OWNER_ONLY,
    # 経路 2。有効な取引関係の発注側にだけ見え、失効すると権限付与ごと閉じる
    "partnerships" => {
      granted_buyer: { supplier: 1 },
      ungranted_buyer: { supplier: 1 }
    },
    "partnership_grants" => {
      granted_buyer: { supplier: 3 }
    }
  }.freeze
end
