require "rails_helper"

# 一覧の 1 ページ（docs/architecture/graphql-schema.md「ページングと N+1」）。並べ替えの列と id の組でたどり、
# 値の無い行を向きによらず最後に置く。どの表でも同じ形なので、基盤が持つ監査ログの表で確かめる
RSpec.describe Page do
  let!(:tenant) { FactoryBot.create(:tenant) }

  def tenancy(&) = Tenancy.with_tenant(tenant.id, &)

  def create_log(**attributes) = tenancy { FactoryBot.create(:audit_log, **attributes) }

  def request_id_sort(direction) = Page::Sort.of([ { field: :request_id, direction: } ], request_id: [ AuditLog.arel_table[:request_id], :string ])

  def page(first:, after: nil, sort: [])
    tenancy do
      described_class.of(AuditLog.all, first:, after:, sort:) { |rows| rows.map(&:id) }.then do |page|
        { values: page.values, cursors: page.cursors, has_next_page: page.has_next_page }
      end
    end
  end

  # 最後のページまで first 件ずつたどり、ページごとの値を返す
  def walk(first:, sort:)
    pages = []
    after = nil
    loop do
      current = page(first:, after:, sort:)
      pages << current[:values]
      break unless current[:has_next_page]

      after = current[:cursors].last
    end
    pages
  end

  describe "並べ替えの列と id の組でたどる" do
    # 列の値が同じ 3 行と値の無い 2 行を、2 件ずつのページの境目にまたがせる
    let!(:logs) do
      { first: create_log(request_id: "r-1"), same: Array.new(3) { create_log(request_id: "r-2") }, last: create_log(request_id: "r-3"),
        blank: Array.new(2) { create_log(request_id: nil) } }
    end

    it "ASC は列の昇順で、値の同じ行を id の昇順に並べ、値の無い行を最後に置く。行は抜けも重なりもしない" do
      pages = walk(first: 2, sort: request_id_sort(:asc))

      expect(pages).to eq([ [ logs[:first].id, logs[:same][0].id ], [ logs[:same][1].id, logs[:same][2].id ],
        [ logs[:last].id, logs[:blank][0].id ], [ logs[:blank][1].id ] ])
    end

    it "DESC は列の降順で、値の同じ行を id の降順に並べ、値の無い行を最後に置く。行は抜けも重なりもしない" do
      pages = walk(first: 2, sort: request_id_sort(:desc))

      expect(pages).to eq([ [ logs[:last].id, logs[:same][2].id ], [ logs[:same][1].id, logs[:same][0].id ],
        [ logs[:first].id, logs[:blank][1].id ], [ logs[:blank][0].id ] ])
    end

    it "列から計算する式でも並べ、カーソルに式の値を書く" do
      length = Page::Sort.of([ { field: :request_id_length, direction: :desc } ],
        request_id_length: [ Arel::Nodes::NamedFunction.new("length", [ AuditLog.arel_table[:request_id] ]), :integer ])
      longer = create_log(request_id: "r-10")

      expect(walk(first: 2, sort: length).flatten)
        .to eq([ longer.id, logs[:last].id, *logs[:same].reverse.map(&:id), logs[:first].id, *logs[:blank].reverse.map(&:id) ])
    end

    it "sort を省くと、id の降順でたどり、カーソルは id のまま" do
      first = page(first: 2)

      expect(first[:cursors]).to eq(first[:values])
      expect(walk(first: 2, sort: []).flatten).to eq(logs.values.flatten.map(&:id).sort.reverse)
    end
  end

  describe "複数の列と id の組でたどる" do
    # 監査ログの action は空にできないので、"-" を空と読み替えた式を 2 つ目の列にする
    let(:columns) do
      table = AuditLog.arel_table
      { request_id: [ table[:request_id], :string ], target_type: [ table[:target_type], :string ],
        action: [ Arel::Nodes::NamedFunction.new("NULLIF", [ table[:action], Arel::Nodes.build_quoted("-") ]), :string ] }
    end

    def sort(*order) = Page::Sort.of(order.map { |field, direction| { field:, direction: } }, columns)

    def create_logs(*rows) = rows.map { |request_id, action, target_type = "Item"| create_log(request_id:, action:, target_type:) }

    it "向きの違う 2 つの列で、1 つ目の列の値が同じ行を 2 つ目の列の向きで並べ、値の無い行をその中の後ろに置く。行は抜けも重なりもしない" do
      logs = create_logs([ "r-1", "a" ], [ "r-1", "b" ], [ "r-1", "-" ], [ "r-1", "b" ], [ "r-2", "a" ])

      expect(walk(first: 2, sort: sort(%i[request_id asc], %i[action desc])))
        .to eq([ [ logs[3].id, logs[1].id ], [ logs[0].id, logs[2].id ], [ logs[4].id ] ])
    end

    # 1 つ目の列が空どうしの行は、空どうしを同じとみなして 2 つ目の列で並べる。= で比べると、カーソルの後ろの行が抜ける
    it "1 つ目の列の値が空の行がページの境目をまたいでも、2 つ目の列の順に抜けも重なりもせずに並ぶ" do
      logs = create_logs([ nil, "b" ], [ nil, "a" ], [ nil, "-" ], [ "r-1", "a" ], [ nil, "a" ])

      expect(walk(first: 1, sort: sort(%i[request_id asc], %i[action asc])).flatten)
        .to eq([ logs[3], logs[1], logs[4], logs[0], logs[2] ].map(&:id))
    end

    it "3 つ目の列は、前の 2 つの列がどちらも同じ行の中で並べ、id を 3 つ目の列と同じ向きに並べる" do
      logs = create_logs([ "r-1", "a", "X" ], [ "r-1", "a", "Y" ], [ "r-1", "b", "Z" ], [ "r-1", "a", "Y" ], [ "r-2", "a", "Z" ])

      expect(walk(first: 1, sort: sort(%i[request_id asc], %i[action asc], %i[target_type desc])).flatten)
        .to eq([ logs[3], logs[1], logs[0], logs[2], logs[4] ].map(&:id))
    end

    it "カーソルは、列ごとの名前・向き・値を順に並べ、最後に id を置く" do
      log = create_logs([ "r-1", "-" ]).sole

      cursor = page(first: 1, sort: sort(%i[request_id asc], %i[action desc]))[:cursors].sole
      expect(JSON.parse(Base64.urlsafe_decode64(cursor))).to eq([ "request_id", "asc", "r-1", "action", "desc", nil, log.id ])
    end

    it "列が 1 つのカーソルは、列の名前・向き・値・id の形のまま読み書きする" do
      logs = create_logs([ "r-1", "a" ], [ "r-2", "a" ])
      single = Base64.urlsafe_encode64(JSON.generate([ "request_id", "asc", "r-1", logs[0].id ]), padding: false)

      expect(page(first: 1, sort: sort(%i[request_id asc]))[:cursors]).to eq([ single ])
      expect(page(first: 1, after: single, sort: sort(%i[request_id asc]))[:values]).to eq([ logs[1].id ])
    end

    it "2 つ目の列の向きだけを変えたカーソルと、列の数の違うカーソルを拒む" do
      create_logs([ "r-1", "a" ], [ "r-1", "b" ])
      two = sort(%i[request_id asc], %i[action asc])
      cursor = page(first: 1, sort: two)[:cursors].sole

      # 対照：同じ並べ替えなら続きを読む
      expect(page(first: 1, after: cursor, sort: two)[:values].size).to eq(1)
      expect { page(first: 1, after: cursor, sort: sort(%i[request_id asc], %i[action desc])) }.to raise_error(Page::InvalidCursor)
      expect { page(first: 1, after: cursor, sort: sort(%i[request_id asc])) }.to raise_error(Page::InvalidCursor)
      single = page(first: 1, sort: sort(%i[request_id asc]))[:cursors].sole
      expect { page(first: 1, after: single, sort: two) }.to raise_error(Page::InvalidCursor)
    end
  end

  describe "金額の和（:decimal）で並べる" do
    # 監査ログの表に金額の列は無いので、request_id の数字を numeric に読み替えて和の代わりにする
    let(:amount) { Arel::Nodes::NamedFunction.new("CAST", [ AuditLog.arel_table[:request_id].as(Arel.sql("numeric")) ]) }

    def amount_sort(direction) = Page::Sort.of([ { field: :amount, direction: } ], amount: [ amount, :decimal ])

    it "bigint の上限を超える和を、カーソルに 10 進の文字列で書き、往復しても行が抜けも重なりもしない" do
      huge = (2**63) * 3
      logs = [ huge, huge, huge + 1, 1 ].map { create_log(request_id: _1.to_s) }
      blank = create_log(request_id: nil)

      expect(walk(first: 1, sort: amount_sort(:asc)).flatten).to eq([ logs[3], logs[0], logs[1], logs[2], blank ].map(&:id))
      expect(walk(first: 1, sort: amount_sort(:desc)).flatten).to eq([ logs[2], logs[1], logs[0], logs[3], blank ].map(&:id))
      cursor = page(first: 1, sort: amount_sort(:desc))[:cursors].sole
      expect(JSON.parse(Base64.urlsafe_decode64(cursor))[2]).to eq((huge + 1).to_s)
    end

    it "31 桁を超える値・負の値・数の値・小数のカーソルを拒み、31 桁ちょうどの値は受け付ける" do
      create_log(request_id: "1")
      id = SecureRandom.uuid
      forge = ->(value) { Base64.urlsafe_encode64(JSON.generate([ "amount", "asc", value, id ]), padding: false) }

      [ "1" * 32, "-1", 1, "1.5", "" ].each do |value|
        expect { page(first: 1, after: forge.call(value), sort: amount_sort(:asc)) }.to raise_error(Page::InvalidCursor), value.inspect
      end
      # 対照：31 桁ちょうどの値は受け付け、SQL で比べられる
      expect(page(first: 1, after: forge.call("9" * 31), sort: amount_sort(:asc))[:values]).to eq([])
      expect(page(first: 1, after: forge.call("0"), sort: amount_sort(:asc))[:values].size).to eq(1)
    end
  end

  describe "Page::Sort.rank" do
    it "式の値を、渡した一覧の中の位置で並べる" do
      logs = %w[b c a].map { create_log(request_id: _1) }
      rank = Page::Sort.of([ { field: :rank, direction: :asc } ], rank: [ Page::Sort.rank(AuditLog.arel_table[:request_id], %i[c a b]), :integer ])

      expect(walk(first: 2, sort: rank).flatten).to eq([ logs[1], logs[2], logs[0] ].map(&:id))
    end
  end

  describe "カーソルの拒否" do
    before { Array.new(3) { create_log(request_id: "r-1") } }

    let(:cursor) { page(first: 1, sort: request_id_sort(:asc))[:cursors].sole }

    def forge(*parts) = Base64.urlsafe_encode64(JSON.generate(parts), padding: false)

    it "向きだけを変えたカーソルを拒む" do
      expect(page(first: 1, after: cursor, sort: request_id_sort(:asc))[:values].size).to eq(1)
      expect { page(first: 1, after: cursor, sort: request_id_sort(:desc)) }.to raise_error(Page::InvalidCursor)
    end

    it "列だけを変えたカーソルを拒む" do
      other = Page::Sort.of([ { field: :action, direction: :asc } ], action: [ AuditLog.arel_table[:action], :string ])

      expect { page(first: 1, after: cursor, sort: other) }.to raise_error(Page::InvalidCursor)
    end

    it "並べ替えを省いた一覧のカーソルと、並べ替えた一覧のカーソルを取り違えると拒む" do
      plain = page(first: 1)[:cursors].sole

      expect { page(first: 1, after: plain, sort: request_id_sort(:asc)) }.to raise_error(Page::InvalidCursor)
      expect { page(first: 1, after: cursor) }.to raise_error(Page::InvalidCursor)
    end

    it "形の誤ったカーソルと、値の型が列と合わないカーソルを拒む" do
      id = SecureRandom.uuid
      integer = Page::Sort.of([ { field: :size, direction: :asc } ], size: [ Arel::Nodes::NamedFunction.new("length", [ AuditLog.arel_table[:action] ]), :integer ])
      date = Page::Sort.of([ { field: :day, direction: :asc } ], day: [ Arel::Nodes::NamedFunction.new("date", [ AuditLog.arel_table[:occurred_at] ]), :date ])

      [ "x", Base64.urlsafe_encode64("[", padding: false), forge("request_id", "asc", "r-1"), forge("request_id", "asc", "r-1", "x"),
        forge("request_id", "asc", 1, id), forge("request_id", "asc", "r\u0000", id) ].each do |after|
        expect { page(first: 1, after:, sort: request_id_sort(:asc)) }.to raise_error(Page::InvalidCursor), after
      end
      expect { page(first: 1, after: forge("size", "asc", "3", id), sort: integer) }.to raise_error(Page::InvalidCursor)
      [ 2_147_483_648, -2_147_483_649 ].each do |value|
        expect { page(first: 1, after: forge("size", "asc", value, id), sort: integer) }.to raise_error(Page::InvalidCursor), value.to_s
      end
      [ "2026-02-30", "5874898-01-01", "0000-12-31" ].each do |value|
        expect { page(first: 1, after: forge("day", "asc", value, id), sort: date) }.to raise_error(Page::InvalidCursor), value
      end
      invalid_utf8 = Base64.urlsafe_encode64("[\"request_id\",\"asc\",\"\xFF\xFE\",\"#{id}\"]".b, padding: false)
      expect { page(first: 1, after: invalid_utf8, sort: request_id_sort(:asc)) }.to raise_error(Page::InvalidCursor)
      # 対照：型の合う値は、範囲の両端まで受け付け、SQL で比べられる
      expect(page(first: 1, after: forge("size", "asc", 2_147_483_647, id), sort: integer)[:values]).to eq([])
      expect(page(first: 1, after: forge("size", "asc", -2_147_483_648, id), sort: integer)[:values].size).to eq(1)
      expect(page(first: 1, after: forge("day", "asc", "5874897-12-31", id), sort: date)[:values]).to eq([])
      expect(page(first: 1, after: forge("day", "asc", "0001-01-01", id), sort: date)[:values].size).to eq(1)
    end
  end

  describe "Page::Sort.of" do
    it "表に無い列と、ASC・DESC でない向きを引数の誤りにする" do
      columns = { request_id: [ AuditLog.arel_table[:request_id], :string ] }

      expect(Page::Sort.of(nil, columns)).to eq([])
      expect { Page::Sort.of([ { field: :action, direction: :asc } ], columns) }.to raise_error(ArgumentError)
      expect { Page::Sort.of([ { field: :request_id, direction: :up } ], columns) }.to raise_error(ArgumentError)
    end

    it "列は 3 つまでを受け付け、4 つと、同じ列の重なりを引数の誤りにする" do
      table = AuditLog.arel_table
      columns = %i[request_id action target_type actor_type].index_with { [ table[_1], :string ] }
      order = ->(*fields) { fields.map { { field: _1, direction: :asc } } }

      expect(Page::Sort.of(order.call(:request_id, :action, :target_type), columns).map(&:name)).to eq(%w[request_id action target_type])
      expect { Page::Sort.of(order.call(:request_id, :action, :target_type, :actor_type), columns) }.to raise_error(ArgumentError)
      expect { Page::Sort.of(order.call(:request_id, :request_id), columns) }.to raise_error(ArgumentError)
      # 1 つの列のハッシュを渡すと、列の配列と取り違えずに引数の誤りにする
      expect { Page::Sort.of({ field: :request_id, direction: :asc }, columns) }.to raise_error(ArgumentError, /not a list/)
    end
  end

  describe "件数" do
    before { Array.new(3) { create_log } }

    def count_sql(&)
      names = []
      counter = ->(*, payload) { names << payload[:sql] unless payload[:cached] || %w[SCHEMA TRANSACTION Tenancy].include?(payload[:name]) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
      names
    end

    it "first と after によらず、ページと同じ relation の行を数える" do
      first = tenancy { described_class.of(AuditLog.all, first: 1, after: nil) { _1.map(&:id) } }
      second = tenancy { described_class.of(AuditLog.all, first: 1, after: tenancy { first.cursors.sole }) { _1.map(&:id) } }

      expect(tenancy { [ first.total_count, second.total_count ] }).to eq([ 3, 3 ])
    end

    it "件数だけを読むと、件数の 1 つの SQL だけを流し、行も値への写しも読まない。行だけを読むと、件数を数えない" do
      mapped = false
      sql = count_sql do
        tenancy { described_class.of(AuditLog.all, first: 2, after: nil) { mapped = true }.total_count }
      end

      expect(sql).to contain_exactly(a_string_matching(/\ASELECT COUNT\(\*\)/))
      expect(mapped).to be(false)
      expect(count_sql { tenancy { described_class.of(AuditLog.all, first: 2, after: nil) { _1.map(&:id) }.values } })
        .to contain_exactly(a_string_matching(/LIMIT/))
    end

    it "Tenancy.with_tenant の外で行と件数を読むと例外にする" do
      built = tenancy { described_class.of(AuditLog.all, first: 2, after: nil) { _1.map(&:id) } }

      expect { built.values }.to raise_error(Tenancy::MissingTenant)
      expect { built.total_count }.to raise_error(Tenancy::MissingTenant)
      expect(tenancy { built.values.size }).to eq(2)
    end

    it "一度読んだ後も、テナントの外と別のテナントの中で読むと例外にする" do
      built = tenancy { described_class.of(AuditLog.all, first: 2, after: nil) { _1.map(&:id) }.tap { [ _1.values, _1.total_count ] } }
      other = FactoryBot.create(:tenant)

      %i[values cursors has_next_page total_count].each do |reader|
        expect { built.public_send(reader) }.to raise_error(Tenancy::MissingTenant), reader.to_s
        expect { Tenancy.with_tenant(other.id) { built.public_send(reader) } }.to raise_error(Tenancy::MissingTenant), reader.to_s
      end
      # 対照：作ったテナントの中なら、読んだ値をそのまま返す
      expect(tenancy { [ built.values.size, built.total_count ] }).to eq([ 2, 3 ])
    end
  end
end
