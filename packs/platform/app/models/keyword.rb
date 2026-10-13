# 一覧の検索の語（docs/architecture/graphql-schema.md「ページングと N+1」）。品目の一覧と在庫の一覧が、同じ規則で検索する
module Keyword
  # 長い値で表を部分一致で走査させないよう、GraphQL の入力型が SQL を流す前に引数の誤りにする上限
  MAX_LENGTH = 100

  # keyword の前後の空白（全角の空白を含む）を除き、columns（Arel の属性）のどれかに含む行に、大文字と小文字を区別せずに絞る。
  # % と _ はワイルドカードにせず、文字として探す。空の keyword は絞らない
  def self.search(relation, keyword, *columns)
    keyword = keyword.to_s.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
    return relation if keyword.empty?

    # sanitize_sql_like は % と _ と \ の前に \ を置く。ESCAPE を明示して DB の既定のエスケープ文字に頼らず、
    # case_sensitive: false で PostgreSQL の ILIKE にする（Arel::Predications#matches、activerecord 8.1）
    pattern = "%#{ApplicationRecord.sanitize_sql_like(keyword)}%"
    relation.where(columns.map { _1.matches(pattern, "\\", false) }.reduce(:or))
  end
end
