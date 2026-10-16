require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

# 受注側の品目の保存。品目コードで引き、無ければ非公開で作り、あれば更新する。公開の状態は変えない（変えるのは set_published と取り込みの bulk_upsert）。
# 新しい品目は最初の単価を持ち、既存の品目の単価は変えない（docs/architecture/graphql-schema.md「mutation の一覧」）
RSpec.describe Sales::Catalog do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) do
    Partnerships::Actor.new(user_id: SecureRandom.uuid, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "")
  end

  around { |example| TenantExample.run(example, supplier.id) }

  def save(code: "N-1", name: "新品目", unit: "個", unit_price: 300, tax_rate_percent: 10)
    described_class.save(actor, code:, name:, unit:, unit_price:, tax_rate_percent:)
  end

  def price_rows = Sales::ItemPrice.pluck(:unit_price, :valid_period)

  it "新しいコードなら非公開で作って最初の単価を有効期間 (,) の行にし、同じコードなら同じ品目を更新する" do
    created = save.value
    expect(created).to have_attributes(code: "N-1", name: "新品目", unit_price: 300, tax_rate_percent: 10, published: false)
    expect(price_rows).to eq([ [ 300, -Float::INFINITY...Float::INFINITY ] ])
    expect(Sales::ItemPrice.sole.recorded_by_user_id).to eq(actor.user_id)

    updated = save(name: "改名", tax_rate_percent: 8).value

    expect(updated).to have_attributes(id: created.id, name: "改名", unit_price: 300, tax_rate_percent: 8)
    expect(described_class.items(actor, first: 10, after: nil).values.map(&:id)).to eq([ created.id ])
    expect(price_rows.size).to eq(1)
  end

  it "既存の品目の今日の単価と違う単価は、単価を指す INVALID_INPUT で、品目も単価も変えない" do
    created = save.value

    result = save(name: "改名", unit_price: 350)

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :invalid_input, [ :unit_price ] ] ])
    expect(described_class.item(actor, created.id)).to have_attributes(name: "新品目", unit_price: 300)
    expect(price_rows.size).to eq(1)
  end

  it "公開した品目を保存しても、公開の状態を変えない" do
    item = save.value
    described_class.set_published(actor, item_id: item.id, published: true)

    expect(save(name: "改名").value).to have_attributes(id: item.id, published: true)
  end

  it "入力の誤りを、項目を指す INVALID_INPUT で返す" do
    failure = ->(result) { result.failures.map { [ _1.code, _1.path ] } }

    expect(failure.(save(tax_rate_percent: 5))).to eq([ [ :invalid_input, [ :tax_rate_percent ] ] ])
    expect(failure.(save(code: ""))).to eq([ [ :invalid_input, [ :code ] ] ])
    expect(failure.(save(unit_price: -1))).to eq([ [ :invalid_input, [ :unit_price ] ] ])
    expect(failure.(save(unit_price: 9_223_372_036_854_775_808))).to eq([ [ :invalid_input, [ :unit_price ] ] ])
    expect(described_class.items(actor, first: 10, after: nil).values).to be_empty
  end

  it "単価は bigint の最大値ちょうどまでを受け付ける" do
    expect(save(unit_price: 9_223_372_036_854_775_807).value).to have_attributes(unit_price: 9_223_372_036_854_775_807)
  end

  it "見えない品目の公開の状態は変えられず、品目 ID を指す NOT_FOUND を返す" do
    result = described_class.set_published(actor, item_id: SecureRandom.uuid, published: true)

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :item_id ] ] ])
  end

  # 一覧の並べ替えと絞り込み（docs/architecture/graphql-schema.md「ページングと N+1」）
  describe ".items" do
    def items(first: 2, **options)
      codes = []
      after = nil
      loop do
        page = described_class.items(actor, first:, after:, **options)
        codes.concat(page.values.map(&:code))
        break [ codes, page.total_count ] unless page.has_next_page

        after = page.cursors.last
      end
    end

    it "品目コードか品目名で、品目コードと ID の組で並べる" do
      [ [ "B-1", "ナット" ], [ "A-1", "ボルト" ], [ "C-1", "ナット" ] ].each { |code, name| FactoryBot.create(:item, code:, name:) }

      expect(items(order_by: [ { field: :code, direction: :asc } ])).to eq([ %w[A-1 B-1 C-1], 3 ])
      expect(items(order_by: [ { field: :name, direction: :desc } ])).to eq([ %w[A-1 C-1 B-1], 3 ])
    end

    # 単価は表示の unit_price と同じ今日の単価で並べる。並べた順と、返った unit_price の値の順が一致する
    it "単位、今日の単価、安全在庫で並べ、値の無い行を向きによらず最後に置く" do
      bolt, _nut, washer = [ [ "B-1", "個", 300 ], [ "N-1", "箱", 50 ], [ "W-1", "個", 120 ] ].map do |code, unit, unit_price|
        FactoryBot.create(:item, code:, unit:, unit_price:)
      end
      [ [ bolt, 5 ], [ washer, 9 ] ].each { |item, safety_stock| FactoryBot.create(:stock, item_id: item.id, safety_stock:) }
      prices = ->(order_by) { [ items(order_by:).first, described_class.items(actor, first: 10, after: nil, order_by:).values.map(&:unit_price) ] }

      expect(items(order_by: [ { field: :unit, direction: :asc }, { field: :code, direction: :desc } ])).to eq([ %w[W-1 B-1 N-1], 3 ])
      expect(prices.call([ { field: :unit_price, direction: :asc } ])).to eq([ %w[N-1 W-1 B-1], [ 50, 120, 300 ] ])
      expect(prices.call([ { field: :unit_price, direction: :desc } ])).to eq([ %w[B-1 W-1 N-1], [ 300, 120, 50 ] ])
      # N-1 は在庫の行が無い
      expect(items(order_by: [ { field: :safety_stock, direction: :asc } ])).to eq([ %w[B-1 W-1 N-1], 3 ])
      expect(items(order_by: [ { field: :safety_stock, direction: :desc } ])).to eq([ %w[W-1 B-1 N-1], 3 ])
    end

    # 単価は bigint まで入る。カーソルの型が integer の範囲しか受け付けないと、2,147,483,647 を超える単価の品目がページの境目に来たときに、
    # 正しいカーソルが Invalid cursor になる
    it "2,147,483,647 を超える単価の品目がページの境目に来ても、そのカーソルで続きを返す" do
      [ [ "A-1", 2_147_483_648 ], [ "B-1", 9_223_372_036_854_775_807 ], [ "C-1", 1 ] ].each do |code, unit_price|
        FactoryBot.create(:item, code:, unit_price:)
      end

      expect(items(first: 1, order_by: [ { field: :unit_price, direction: :asc } ])).to eq([ %w[C-1 A-1 B-1], 3 ])
      expect(items(first: 1, order_by: [ { field: :unit_price, direction: :desc } ])).to eq([ %w[B-1 A-1 C-1], 3 ])
    end

    # 単価の行は、訂正で閉じた行と、今日より後に予約した改定の行も持つ。並びは表示と同じく、いま信じている今日の単価だけを使う
    it "訂正した単価は訂正の後の値で、予約した改定は今日の値で並べる" do
      corrected, revised = [ [ "A-1", 100 ], [ "B-1", 200 ], [ "C-1", 150 ] ].map { |code, unit_price| FactoryBot.create(:item, code:, unit_price:) }
      row = Sales::ItemPrices.history(actor, [ corrected.id ]).fetch(corrected.id).sole
      expect(Sales::ItemPrices.correct(actor, item_price_id: row.id, unit_price: 500, reason: "入力の誤り")).to be_success
      expect(Sales::ItemPrices.schedule(actor, item_id: revised.id, unit_price: 10, effective_on: Sales::ItemPrice.today + 1)).to be_success

      expect(items(first: 1, order_by: [ { field: :unit_price, direction: :asc } ])).to eq([ %w[C-1 B-1 A-1], 3 ])
    end

    it "keyword は、前後の空白を除いて、品目コードか品目名に含む品目に、大文字と小文字を区別せずに絞る。空なら絞らない" do
      [ [ "BOLT-8", "六角ボルト" ], [ "nut-1", "Bolt 用ナット" ], [ "W-1", "ワッシャー" ] ].each { |code, name| FactoryBot.create(:item, code:, name:) }

      expect(items(filter: { keyword: "  bolt\u3000" })).to eq([ %w[nut-1 BOLT-8], 2 ])
      expect(items(filter: { keyword: "ボルト" })).to eq([ %w[BOLT-8], 1 ])
      expect(items(filter: { keyword: "NUT" })).to eq([ %w[nut-1], 1 ])
      expect(items(filter: { keyword: " " })[1]).to eq(3)
      expect(items(filter: { keyword: nil })[1]).to eq(3)
    end

    # 品目名の列の照合順序 ja-x-icu は、漢字を音読みの順（平のヘイが六のロクより前）で並べ、流用元の Intl.Collator("ja") と
    # 同じ並びになる。コードポイントの順では六角の 2 つが先になる。2 件ずつのページの境目のカーソルも同じ照合順序で比べる
    it "品目名を、漢字の音読みの順に並べる" do
      [ [ "N-2", "六角ナット M8" ], [ "B-1", "六角ボルト M8" ], [ "W-3", "平座金 M8" ] ].each { |code, name| FactoryBot.create(:item, code:, name:) }

      expect(items(order_by: [ { field: :name, direction: :asc } ])).to eq([ %w[W-3 N-2 B-1], 3 ])
    end

    # 品目コードの列（pg_c_utf8）は ASCII の外の文字も、品目名の列（ja-x-icu）は全角の英字も、大文字と小文字を区別せずに探す。
    # 全角と半角は別の文字として扱う
    it "keyword は、ASCII の外の文字と全角の英字の大文字と小文字を区別せず、全角と半角は区別する" do
      [ [ "Ä-1", "ＡＢＣ継手" ], [ "Ö-2", "abc 継手" ] ].each { |code, name| FactoryBot.create(:item, code:, name:) }

      expect(items(filter: { keyword: "ä-" })).to eq([ %w[Ä-1], 1 ])
      expect(items(filter: { keyword: "ａｂｃ" })).to eq([ %w[Ä-1], 1 ])
      expect(items(filter: { keyword: "ABC" })).to eq([ %w[Ö-2], 1 ])
    end

    it "keyword の % と _ と \\ は、ワイルドカードではなく文字として扱う" do
      [ "50%OFF", "A_1", "A\\1", "AB1", "500FF" ].each { FactoryBot.create(:item, code: _1) }

      expect(items(filter: { keyword: "%" })).to eq([ %w[50%OFF], 1 ])
      expect(items(filter: { keyword: "_" })).to eq([ %w[A_1], 1 ])
      expect(items(filter: { keyword: "\\" })).to eq([ [ "A\\1" ], 1 ])
      # 対照：ワイルドカードでない文字は、そのまま部分一致で絞る
      expect(items(filter: { keyword: "A" })[1]).to eq(3)
    end
  end
end

# 在庫の一覧が品目のコードと名前で並べ、検索する写し（docs/architecture/data-model.md「在庫（`inventory`）」、docs/adr/011）。
# 保存は同じトランザクションで写しを書き、作り直しは自社の全品目の写しを書き直して、足した数と書き直した数を返す
RSpec.describe Sales::Catalog, "の品目の写し" do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) do
    Partnerships::Actor.new(user_id: SecureRandom.uuid, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "")
  end

  def mine(&) = Tenancy.with_tenant(supplier.id, &)

  def save(code: "N-1", name: "ナット", unit_price: 300)
    mine { described_class.save(actor, code:, name:, unit: "個", unit_price:, tax_rate_percent: 10) }
  end

  # 写しのモデルは在庫のパッケージの外に出さないので、SQL で読む。RLS がテナントの写しだけを見せる
  def label_rows(columns) = ActiveRecord::Base.lease_connection.select_rows("SELECT #{columns} FROM item_labels")

  def labels_of(tenant) = Tenancy.with_tenant(tenant.id) { label_rows("item_id, code, name") }

  def counts(inserted, updated) = Inventory::ItemLabels::Counts.new(inserted:, updated:)

  describe ".save" do
    it "品目のコードと名前を在庫の写しへ書き、名前を変えれば写しも変え、保存しなかった品目の写しは変えない" do
      item = save.value
      expect(labels_of(supplier)).to eq([ [ item.id, "N-1", "ナット" ] ])

      save(name: "六角ナット")
      expect(labels_of(supplier)).to eq([ [ item.id, "N-1", "六角ナット" ] ])

      expect(save(name: "改名", unit_price: 999)).not_to be_success
      expect(labels_of(supplier)).to eq([ [ item.id, "N-1", "六角ナット" ] ])
    end
  end

  describe ".rebuild_item_labels" do
    def rebuild = mine { described_class.rebuild_item_labels }

    it "写しの無い品目に足し、値の違う写しを書き直して、それぞれの数を返す。一致していれば両方 0 になる" do
      bolt, nut, washer = mine { [ %w[B-1 ボルト], %w[N-1 ナット], %w[W-1 座金] ].map { FactoryBot.create(:item, code: _1, name: _2) } }
      mine { Inventory::ItemLabels.put([ { item_id: nut.id, code: "N-1", name: "古い名前" }, { item_id: washer.id, code: "W-1", name: "座金" } ]) }

      expect(rebuild).to eq(counts(1, 1))
      expect(labels_of(supplier)).to contain_exactly([ bolt.id, "B-1", "ボルト" ], [ nut.id, "N-1", "ナット" ], [ washer.id, "W-1", "座金" ])
      expect(rebuild).to eq(counts(0, 0))
    end

    it "テナントの設定の外では例外にする" do
      expect { described_class.rebuild_item_labels }.to raise_error(Tenancy::MissingTenant)
    end

    # 品目の表には公開した品目を取引先に見せる SELECT のポリシーがあるので、所有の条件を RLS に任せられない。
    # RLS の SELECT と UPDATE を開き、他社の品目が見える状態で、自社の品目だけを写すことを確かめる
    # （docs/guides/testing.md「行列テストとの分担」）
    describe "RLS の SELECT と UPDATE を開いたとき" do
      include_context "RLS の SELECT と UPDATE を開く"

      it "他社の品目が見えても、自社の品目だけを読んで写す" do
        theirs = Tenancy.with_tenant(other.id) { FactoryBot.create(:item, code: "X-1", name: "他社の品目") }
        own = mine { FactoryBot.create(:item, code: "M-1", name: "自社の品目") }

        mine do
          cross_read!
          # 対照：開いた後は他社の品目が見える
          expect(Sales::Item.where(id: [ own.id, theirs.id ]).pluck(:id)).to contain_exactly(own.id, theirs.id)

          expect(described_class.rebuild_item_labels).to eq(counts(1, 0))
          expect(label_rows("owner_tenant_id, item_id")).to eq([ [ supplier.id, own.id ] ])
        end
      end
    end
  end
end

# 品目の一覧の安全在庫は、在庫の公開 API の副問い合わせから引く（docs/architecture/graphql-schema.md「ページングと N+1」）。
# 品目 ID は UUIDv7 で他社の品目と重ならないので、副問い合わせから所有の条件を外しても入口の行列では捕まらない。
# RLS の SELECT と UPDATE を開き、他社の名義で自社の品目 ID を指す在庫の行が見える状態で確かめる（docs/guides/testing.md「行列テストとの分担」）
RSpec.describe Sales::Catalog, "の安全在庫での並べ替え" do
  include_context "RLS の SELECT と UPDATE を開く"

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  it "他社の名義で自社の品目 ID を指す在庫の行を、安全在庫の並びに使わない" do
    unstocked = Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:item, code: "A-1").tap { FactoryBot.create(:stock, item_id: _1.id, safety_stock: 5) }
      FactoryBot.create(:item, code: "B-1")
    end
    Tenancy.with_tenant(other.id) { FactoryBot.create(:stock, item_id: unstocked.id, safety_stock: 1) }

    Tenancy.with_tenant(supplier.id) do
      cross_read!
      # 対照：開いた後は、自社の品目 ID を指す他社の在庫の行が見える
      expect(Inventory::Stocks.for_items(actor, [ unstocked.id ])).to be_empty
      expect(ActiveRecord::Base.lease_connection.select_values("SELECT owner_tenant_id FROM stocks WHERE item_id = $1", "SQL", [ unstocked.id ]))
        .to eq([ other.id ])

      # 他社の在庫の 1 を使うと、B-1 が A-1 より前に並ぶ
      codes = described_class.items(actor, first: 10, after: nil, order_by: [ { field: :safety_stock, direction: :asc } ]).values.map(&:code)
      expect(codes).to eq(%w[A-1 B-1])
    end
  end
end
