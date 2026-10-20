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
  # 金額の和は、明細の件数の上限（100）・数量の上限（integer）・単価の上限（bigint）の積を超えないので 31 桁に収まる。
  # bigint を超えうるので、JSON の数ではなく 10 進の文字列でカーソルに書く
  DECIMAL = /\A\d{1,31}\z/

  # 並べ替えの列の数の上限。カーソルの後ろの条件は、列の数の 2 乗で長くなる
  MAX_SORTS = 3

  # 並べ替えの列。name はカーソルに書く名前、expression は一覧の表の列か、その列から計算する式か、行ごとに 1 つの値を返す
  # スカラーの副問い合わせ（Arel のノード）、
  # type はカーソルの値の型（:string・:date・:integer・:decimal）、direction は :asc か :desc。:decimal は 0 以上の整数の値に限る
  Sort = Data.define(:name, :expression, :type, :direction) do
    # order_by は { field:, direction: } の配列で、1 つ目の列から順に並べる。nil は空の配列と同じく、空の配列を返す。
    # columns は並べてよい列の名前ごとの [式, 型] で、配列でない order_by・無い列・同じ列の重なり・MAX_SORTS を超える数は引数の誤りにする
    def self.of(order_by, columns)
      raise ArgumentError, "order_by is not a list: #{order_by.class}" unless order_by.nil? || order_by.is_a?(Array)

      order_by = order_by.to_a
      raise ArgumentError, "too many order fields: #{order_by.size}" if order_by.size > MAX_SORTS
      raise ArgumentError, "repeated order field" unless order_by.uniq { _1.fetch(:field) }.size == order_by.size

      order_by.map do |each|
        field = each.fetch(:field)
        direction = each.fetch(:direction)
        raise ArgumentError, "unknown order field: #{field}" unless columns.key?(field)
        raise ArgumentError, "unknown order direction: #{direction}" unless Sort::DIRECTIONS.include?(direction)

        expression, type = columns.fetch(field)
        new(name: field.to_s, expression:, type:, direction:)
      end
    end

    # 式の値の、order の中の位置（1 から）。状況を業務の進み順で並べるのに使う。order に無い値は空になり、最後に並ぶ
    def self.rank(expression, order)
      values = ApplicationRecord.with_connection { |connection| order.map { connection.quote(_1.to_s) } }
      Arel::Nodes::NamedFunction.new("array_position", [ Arel.sql("ARRAY[#{values.join(", ")}]::text[]"), expression ])
    end
  end
  # Sort.of が受け付ける向き。GraphQL の enum が写すので、of が読む一覧を定数に出す。Data.define のブロックの中の定数は
  # Sort ではなく Page に付くので、ブロックの外で Sort に置く
  Sort::DIRECTIONS = %i[asc desc].freeze

  # relation を並べ、after より後の first 件を引いて、ブロックで値に写すページを返す。
  # sort を省くと、一意な列 key の順に並べ、key の値をカーソルにする。:id（UUIDv7）なら作成順の新しいものから並べる。
  # sort（Sort の配列）を渡すと「列 1、列 2、…、id」の組で並べ、id を最後の列と同じ向きに並べる。値の無い行は列ごとに向きによらず後ろに置く。
  # 件数は first と after によらず、relation の行を数える。
  # columns は行と一緒に読む式（Arel の As のノード）で、行には、その別名の属性で載る。relation に select を掛けて渡すと、
  # 件数の count が select の複数の列を COUNT に渡して SQL のエラーになるので、行の列は relation と別に受け取り、件数の SQL に入れない
  def self.of(relation, first:, after:, key: :id, direction: :desc, sort: [], columns: [], &to_values)
    rows = sort.empty? ? keyed(relation, key, direction, after) : sorted(relation, sort, after)
    columns += sort.each_with_index.map { |each, i| each.expression.as("page_sort_value_#{i}") }
    rows = rows.select(relation.arel_table[Arel.star], *columns)
    cursor = sort.empty? ? ->(record) { record.public_send(key).to_s } : ->(record) { encode(sort, record) }
    new(rows: rows.limit(first + 1), first:, cursor:, count: -> { relation.count }, to_values:)
  end

  def self.keyed(relation, key, direction, after)
    if after
      raise InvalidCursor, "invalid cursor" if key == :id && !after.match?(UUID)

      relation = relation.where(relation.arel_table[key].public_send(direction == :desc ? :lt : :gt, after))
    end
    relation.reorder(key => direction)
  end

  # カーソルの後ろの行は、「ある列より前の列がすべてカーソルと同じ値で、その列がカーソルより後」のどれかか、
  # 「すべての列が同じ値で、id が後」である。前の列が同じことは、空どうしも同じとみなす IS NOT DISTINCT FROM で比べる。
  # = で比べると、前の列の値が空の行で、後ろの列がカーソルより後の行が抜ける
  def self.sorted(relation, sorts, after)
    id = relation.arel_table[:id]
    if after
      values, after_id = decode(sorts, after)
      same = sorts.zip(values).map { |sort, value| sort.expression.is_not_distinct_from(value) }
      later = sorts.zip(values).each_with_index.filter_map do |(sort, value), i|
        column = later_value(sort, value)
        column && [ *same.first(i), column ].reduce(:and)
      end
      relation = relation.where([ *later, [ *same, id.public_send(later_operator(sorts.last), after_id) ].reduce(:and) ].reduce(:or))
    end
    relation.reorder(*sorts.map { _1.expression.public_send(_1.direction).nulls_last }, id.public_send(sorts.last.direction))
  end

  # 1 つの列の値がカーソルより後の条件。値の無い行を後ろに置くので、カーソルの値が空なら後は無く（nil を返す）、
  # 値があれば「値が後か、値が空」になる
  def self.later_value(sort, value)
    return if value.nil?

    sort.expression.public_send(later_operator(sort), value).or(sort.expression.eq(nil))
  end

  def self.later_operator(sort) = sort.direction == :desc ? :lt : :gt

  # カーソルは、列ごとの名前・向き・値を順に並べ、最後に id を置いた配列を JSON にして Base64 で包む。
  # 列の名前と向きも持たせ、別の並べ替えで作ったカーソルを拒めるようにする。列が 1 つなら、名前・向き・値・id の 4 つを並べた形になる
  def self.encode(sorts, record)
    parts = sorts.each_with_index.flat_map do |sort, i|
      value = record["page_sort_value_#{i}"]
      value = value.iso8601 if value.is_a?(Date)
      value = value.to_i.to_s if sort.type == :decimal && value
      [ sort.name, sort.direction.to_s, value ]
    end
    Base64.urlsafe_encode64(JSON.generate([ *parts, record.id ]), padding: false)
  end

  # 列の数・名前・向きのどれかが違うカーソルは、形の誤ったカーソルと同じく拒む
  def self.decode(sorts, after)
    *parts, id = JSON.parse(Base64.urlsafe_decode64(after))
    columns = parts.each_slice(3).to_a
    unless parts.size == sorts.size * 3 && columns.map { _1.first(2) } == sorts.map { [ _1.name, _1.direction.to_s ] } &&
        id.is_a?(String) && id.match?(UUID)
      raise InvalidCursor, "invalid cursor"
    end

    [ sorts.zip(columns).map { |sort, (_, _, value)| value.nil? ? nil : cast(sort.type, value) }, id ]
  rescue ArgumentError, TypeError, NoMatchingPatternError, JSON::ParserError
    raise InvalidCursor, "invalid cursor"
  end

  # カーソルの値を列の型に戻す。型の合わない値は NoMatchingPatternError にし、decode が形の誤りにする
  def self.cast(type, value)
    case [ type, value ]
    in [ :string, String ] if value.valid_encoding? && !value.include?("\u0000") then value
    in [ :integer, Integer ] if INTEGER.cover?(value) then value
    in [ :date, String ] if DATE.cover?(date = Date.iso8601(value)) then date
    # Integer で比べると、Active Record が bigint を超える整数を引数の誤りにするので、numeric の BigDecimal で比べる
    # （activerecord 8.1 の ActiveRecord.raise_int_wider_than_64bit の既定は true で、
    # connection_adapters/postgresql/quoting.rb の check_int_in_range が IntegerOutOf64BitRange を投げる）
    in [ :decimal, String ] if value.match?(DECIMAL) then BigDecimal(value)
    end
  end
  private_class_method :keyed, :sorted, :later_value, :later_operator, :encode, :decode, :cast

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
