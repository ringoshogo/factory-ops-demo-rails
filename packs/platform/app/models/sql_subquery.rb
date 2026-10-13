# 公開 API が、別のコンテキストの SQL の中へ値を渡すときの副問い合わせ（docs/adr/010-状況の導出をSQLの式1つにする.md）。
# 操作者の scope を掛けた relation（所有テナントの無い表は、scope の代わりに返す列を絞った relation）を SQL の文字列にしたものと、その列の名前だけを持つ。relation を渡すと、受け取る側が
# unscope・rewhere・update_all を呼べ、scope と書き込みの入口がコンテキストの境界を越えるからである。
# 受け取る側は、条件を足さずに副問い合わせとして結ぶだけにする
SqlSubquery = Data.define(:sql, :columns) do
  # columns は役割ごとの列の名前（{ line_id: "sales_order_line_id" } の形）で、relation が select した列の別名を書く
  def self.of(relation, **columns)
    new(sql: relation.to_sql.freeze, columns: columns.transform_values { _1.to_s.freeze }.freeze)
  end

  # 副問い合わせを name の別名で結ぶ Arel のノード。結ぶ側は、これを JOIN し、column の列で条件を書く
  def as(name) = Arel::Nodes::TableAlias.new(Arel::Nodes::Grouping.new(Arel.sql(sql)), name)

  def column(table_alias, role) = table_alias[columns.fetch(role)]

  # key の役割の列が value に等しい 1 行の、role の役割の列を引くスカラーの副問い合わせ（Arel のノード）。
  # 結ぶ側の行ごとに 1 つの値を返すので、結合と違って結ぶ側の行の数を変えない。当たる行が無ければ空になり、
  # 2 行以上当たれば SQL のエラーになる
  def lookup(role, key, value)
    table = as("lookup")
    Arel::Nodes::Grouping.new(Arel::SelectManager.new(table).project(column(table, role)).where(column(table, key).eq(value)))
  end
end
