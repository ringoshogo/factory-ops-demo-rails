# 公開 API が一覧を返すときの 1 ページ。cursors は values と同じ順の、値ごとのカーソル。
# GraphQL 層がコネクションに包む（docs/architecture/graphql-schema.md「ページングと N+1」）。
# 行と件数は、初めて読まれたときに引く。件数だけを選ぶ問い合わせは、ページの行も値への写しも読まない
class Page
  class InvalidCursor < StandardError; end

  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  # カーソルの値として受け付ける範囲。範囲の外の値をカーソルに書き換えると、比べる SQL がエラーになり、
  # 形の誤ったカーソルのトップレベルのエラーではなく 500 になる。整数は PostgreSQL の integer の範囲、
  # 日付は PostgreSQL の date の上限（5874897 年）までで、紀元前の日付は扱わない
  INTEGER = -(2**31)..(2**31 - 1)
  DATE = Date.new(1, 1, 1)..Date.new(5_874_897, 12, 31)

  # 並べ替えの列。name はカーソルに書く名前、expression は一覧の表の列か、その列から計算する式（Arel のノード）、
  # type はカーソルの値の型（:string・:date・:integer）、direction は :asc か :desc
  Sort = Data.define(:name, :expression, :type, :direction) do
    # order_by は { field:, direction: }。columns は並べてよい列の名前ごとの [式, 型] で、無い列は引数の誤りにする
    def self.of(order_by, columns)
      return if order_by.nil?

      field = order_by.fetch(:field)
      direction = order_by.fetch(:direction)
      raise ArgumentError, "unknown order field: #{field}" unless columns.key?(field)
      raise ArgumentError, "unknown order direction: #{direction}" unless %i[asc desc].include?(direction)

      expression, type = columns.fetch(field)
      new(name: field.to_s, expression:, type:, direction:)
    end
  end

  # relation を並べ、after より後の first 件を引いて、ブロックで値に写すページを返す。
  # sort を省くと、一意な列 key の順に並べ、key の値をカーソルにする。:id（UUIDv7）なら作成順の新しいものから並べる。
  # sort を渡すと「列の値、id」の組で並べ、id を列と同じ向きに並べる。値の無い行は向きによらず最後に置く。
  # 件数は first と after によらず、relation の行を数える
  def self.of(relation, first:, after:, key: :id, direction: :desc, sort: nil, &to_values)
    rows = sort ? sorted(relation, sort, after) : keyed(relation, key, direction, after)
    cursor = sort ? ->(record) { encode(sort, record) } : ->(record) { record.public_send(key).to_s }
    new(rows: rows.limit(first + 1), first:, cursor:, count: -> { relation.count }, to_values:)
  end

  def self.keyed(relation, key, direction, after)
    if after
      raise InvalidCursor, "invalid cursor" if key == :id && !after.match?(UUID)

      relation = relation.where(relation.arel_table[key].public_send(direction == :desc ? :lt : :gt, after))
    end
    relation.reorder(key => direction)
  end

  # 値の無い行を最後に置くので、カーソルの値が空なら、後ろは「値が空で id が後のもの」だけになる。
  # 値があれば、後ろは「値が後のもの、値が同じで id が後のもの、値が空のもの」になる
  def self.sorted(relation, sort, after)
    id = relation.arel_table[:id]
    later = sort.direction == :desc ? :lt : :gt
    if after
      value, after_id = decode(sort, after)
      relation = if value.nil?
        relation.where(sort.expression.eq(nil).and(id.public_send(later, after_id)))
      else
        relation.where(sort.expression.public_send(later, value)
          .or(sort.expression.eq(value).and(id.public_send(later, after_id)))
          .or(sort.expression.eq(nil)))
      end
    end
    relation.select(relation.arel_table[Arel.star], sort.expression.as("page_sort_value"))
      .reorder(sort.expression.public_send(sort.direction).nulls_last, id.public_send(sort.direction))
  end

  # カーソルは、並べ替えの列の名前・向き・列の値・id を JSON にして Base64 で包む。
  # 列の名前と向きも持たせ、別の並べ替えで作ったカーソルを拒めるようにする
  def self.encode(sort, record)
    value = record["page_sort_value"]
    value = value.iso8601 if value.is_a?(Date)
    Base64.urlsafe_encode64(JSON.generate([ sort.name, sort.direction.to_s, value, record.id ]), padding: false)
  end

  def self.decode(sort, after)
    name, direction, value, id, *rest = JSON.parse(Base64.urlsafe_decode64(after))
    unless rest.empty? && [ name, direction ] == [ sort.name, sort.direction.to_s ] && id.is_a?(String) && id.match?(UUID)
      raise InvalidCursor, "invalid cursor"
    end

    [ value.nil? ? nil : cast(sort.type, value), id ]
  rescue ArgumentError, TypeError, NoMatchingPatternError, JSON::ParserError
    raise InvalidCursor, "invalid cursor"
  end

  # カーソルの値を列の型に戻す。型の合わない値は NoMatchingPatternError にし、decode が形の誤りにする
  def self.cast(type, value)
    case [ type, value ]
    in [ :string, String ] if value.valid_encoding? && !value.include?("\u0000") then value
    in [ :integer, Integer ] if INTEGER.cover?(value) then value
    in [ :date, String ] if DATE.cover?(date = Date.iso8601(value)) then date
    end
  end
  private_class_method :keyed, :sorted, :encode, :decode, :cast

  def initialize(rows:, first:, cursor:, count:, to_values:)
    @rows = rows
    @first = first
    @cursor = cursor
    @count = count
    @to_values = to_values
    @tenant_id = Current.tenant_id
  end

  def values = loaded.fetch(:values)

  def cursors = loaded.fetch(:cursors)

  def has_next_page = loaded.fetch(:has_next_page)

  def total_count
    within_tenant { @total_count ||= @count.call }
  end

  private

  def loaded
    within_tenant do
      @loaded ||= begin
        records = @rows.to_a
        page = records.first(@first)
        { values: @to_values.call(page), cursors: page.map(&@cursor), has_next_page: records.size > @first }
      end
    end
  end

  # 行を後で引くので、ページを作ったテナントの外で読むと、RLS が行を隠して空のページを黙って返す。そうせずに例外にする。
  # 一度読んだ値も、別のテナントの中で読めば別のテナントの値を渡すことになるので、読むたびに確かめる
  def within_tenant
    raise Tenancy::MissingTenant, "Page を、作った Tenancy.with_tenant の外で読んだ" if Current.tenant_id != @tenant_id

    yield
  end
end
