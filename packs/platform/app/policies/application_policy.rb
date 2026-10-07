# 各コンテキストの policy の基底。user には操作者（Partnerships::Actor）が入る。
# 規則を書かなければ拒否する（ActionPolicy::Base の既定の規則はすべて偽）
class ApplicationPolicy < ActionPolicy::Base
  # 1 回の GraphQL の実行の間だけ使うハッシュ。返すオブジェクトごとに規則を評価する Types::BaseObject が渡す
  # （docs/architecture/graphql-schema.md「ページングと N+1」）
  authorize :request_memo, optional: true

  private

  # 規則の中の、オブジェクトによらない問い合わせの答えを、request_memo があれば 1 回の実行の間使い回す
  def remember(key)
    return yield unless request_memo

    request_memo.fetch(key) { request_memo[key] = yield }
  end
end
