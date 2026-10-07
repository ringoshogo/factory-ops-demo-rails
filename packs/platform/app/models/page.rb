# 公開 API が一覧を返すときの 1 ページ。cursors は values と同じ順の、値ごとのカーソル。
# GraphQL 層がコネクションに包む（docs/architecture/graphql-schema.md「ページングと N+1」）
Page = Data.define(:values, :cursors, :has_next_page)

class Page
  class InvalidCursor < StandardError; end

  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  # relation を key の順に並べ、after より後の first 件を引いて、ブロックで値に写す。
  # key は一意な列にする。:id（UUIDv7）なら作成順の新しいものから並べる
  def self.of(relation, first:, after:, key: :id, direction: :desc, &to_values)
    if after
      raise InvalidCursor, "invalid cursor" if key == :id && !after.match?(UUID)

      relation = relation.where(relation.arel_table[key].public_send(direction == :desc ? :lt : :gt, after))
    end
    records = relation.reorder(key => direction).limit(first + 1).to_a
    page = records.first(first)

    new(values: to_values.call(page), cursors: page.map { _1.public_send(key).to_s }, has_next_page: records.size > first)
  end
end
