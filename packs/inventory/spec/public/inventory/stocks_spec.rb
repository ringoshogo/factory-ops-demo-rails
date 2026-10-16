require "rails_helper"
require_relative "../../../../../spec/support/cross_read"
require_relative "../../../../../spec/support/env_helpers"

# ダッシュボードの安全在庫。有効在庫（現在庫 - 引当）が安全在庫より小さい在庫だけを返し、等しい在庫は返さない
# （docs/architecture/data-model.md「在庫（`inventory`）」、docs/architecture/graphql-schema.md「読み取りの一覧」）
RSpec.describe Inventory::Stocks do
  include EnvHelpers

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  def below_safety_stock(limit: 100) = Tenancy.with_tenant(supplier.id) { described_class.below_safety_stock(actor, limit:) }

  describe ".below_safety_stock" do
    it "有効在庫が安全在庫より 1 小さい在庫を返し、等しい在庫と大きい在庫を返さない。引当を差し引いて比べる" do
      below, equal, above, allocated_below = Tenancy.with_tenant(supplier.id) do
        [ FactoryBot.create(:stock, on_hand: 4, safety_stock: 5),
          FactoryBot.create(:stock, on_hand: 5, safety_stock: 5),
          FactoryBot.create(:stock, on_hand: 6, safety_stock: 5),
          FactoryBot.create(:stock, on_hand: 10, allocated: 6, safety_stock: 5) ]
      end

      expect(below_safety_stock.map(&:item_id)).to match_array([ below.item_id, allocated_below.item_id ])
      expect(below_safety_stock).to all(have_attributes(below_safety_stock: true))
      expect([ equal, above ].map(&:item_id) & below_safety_stock.map(&:item_id)).to be_empty
    end

    it "他社の在庫を返さない" do
      own = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:stock, on_hand: 0, safety_stock: 1) }
      Tenancy.with_tenant(other.id) { FactoryBot.create(:stock, on_hand: 0, safety_stock: 1) }

      # 対照：同じ条件の自社の在庫は返る
      expect(below_safety_stock.map(&:item_id)).to eq([ own.item_id ])
    end

    # 写しのコードが同じ在庫は無いが、写しの無い在庫どうしは品目 ID で並ぶ
    it "品目の写しのコードの順に並べ、写しの無い在庫を最後に品目 ID の順で並べる" do
      ids = Tenancy.with_tenant(supplier.id) do
        labeled = %w[BOLT-1 AXLE-1 NUT-1].to_h do |code|
          [ code, FactoryBot.create(:stock, on_hand: 0, safety_stock: 1).tap { FactoryBot.create(:item_label, item_id: _1.item_id, code:) }.item_id ]
        end
        unlabeled = Array.new(2) { FactoryBot.create(:stock, on_hand: 0, safety_stock: 1).item_id }.sort
        [ *labeled.values_at("AXLE-1", "BOLT-1", "NUT-1"), *unlabeled ]
      end

      expect(below_safety_stock.map(&:item_id)).to eq(ids)
    end

    it "上限ちょうどの在庫はすべて返し、上限 + 1 の在庫は並びの先頭から上限の件数だけ返す" do
      stock = ->(code) { FactoryBot.create(:stock, on_hand: 0, safety_stock: 1).tap { FactoryBot.create(:item_label, item_id: _1.item_id, code:) } }
      first, second = Tenancy.with_tenant(supplier.id) { %w[A-1 B-1].map { stock.(_1).item_id } }

      expect(below_safety_stock(limit: 2).map(&:item_id)).to eq([ first, second ])

      Tenancy.with_tenant(supplier.id) { stock.("C-1") }
      expect(below_safety_stock(limit: 2).map(&:item_id)).to eq([ first, second ])
      # 対照：上限を広げれば 3 件目も返る
      expect(below_safety_stock(limit: 3).size).to eq(3)
    end
  end

  # シードと E2E の世界の準備のための安全在庫の設定。自社の在庫の行だけを変え、数量と移動履歴には触れない。
  # 本番の環境では DEMO_WORLD_ENABLED=1 のときだけ呼べる（docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
  # 受注の品目の一覧が安全在庫で並べるために結ぶ副問い合わせ。他社の在庫を使わないことは、RLS を開いた
  # packs/sales/spec/public/sales/catalog_spec.rb が確かめる
  describe ".safety_stocks_sql" do
    it "自社の在庫の品目 ID と安全在庫を、役割の名前の列で返す" do
      own = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:stock, safety_stock: 7) }
      Tenancy.with_tenant(other.id) { FactoryBot.create(:stock, safety_stock: 9) }

      rows = Tenancy.with_tenant(supplier.id) do
        subquery = described_class.safety_stocks_sql(actor)
        table = subquery.as("s")
        ActiveRecord::Base.lease_connection.select_rows(
          Arel::SelectManager.new(table).project(subquery.column(table, :item_id), subquery.column(table, :safety_stock)).to_sql
        )
      end
      expect(rows).to eq([ [ own.item_id, 7 ] ])
    end
  end

  describe ".set_safety_stock" do
    let!(:own) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:stock, on_hand: 10, safety_stock: 3) } }
    let!(:theirs) { Tenancy.with_tenant(other.id) { FactoryBot.create(:stock, on_hand: 10, safety_stock: 3) } }

    def set(item_id, safety_stock) = Tenancy.with_tenant(supplier.id) { described_class.set_safety_stock(actor, item_id:, safety_stock:) }

    def failures(result) = result.failures.map { [ _1.code, _1.path ] }

    # アプリのロールの接続で、テナントを設定して生 SQL で読む。RLS が、設定したテナントの行だけを見せる
    def safety_stock_seen_by(tenant, item_id)
      Tenancy.with_tenant(tenant.id) do
        ActiveRecord::Base.lease_connection.select_value("SELECT safety_stock FROM stocks WHERE item_id = $1", "SQL", [ item_id ])
      end
    end

    it "自社の在庫の安全在庫を変え、数量と移動履歴は変えない" do
      result = set(own.item_id, 12)

      expect(result.value).to have_attributes(item_id: own.item_id, on_hand: 10, safety_stock: 12, below_safety_stock: true)
      expect(safety_stock_seen_by(supplier, own.item_id)).to eq(12)
      expect(Tenancy.with_tenant(supplier.id) { Inventory::StockMovement.where(item_id: own.item_id).count }).to eq(0)
    end

    it "今と同じ値も成功し、何も変えない" do
      expect(set(own.item_id, 3).value).to have_attributes(item_id: own.item_id, safety_stock: 3)
      expect(set(own.item_id, 12)).to be_success
      expect(set(own.item_id, 12).value).to have_attributes(safety_stock: 12, on_hand: 10)
      expect(safety_stock_seen_by(supplier, own.item_id)).to eq(12)
    end

    it "他社の品目は NOT_FOUND で、他社の在庫を書かない" do
      expect(failures(set(theirs.item_id, 99))).to eq([ [ :not_found, [ :item_id ] ] ])
      # 対照：他社の設定の生 SQL は他社の在庫を読み、値は元のままである
      expect(safety_stock_seen_by(other, theirs.item_id)).to eq(3)
      expect(safety_stock_seen_by(supplier, theirs.item_id)).to be_nil
    end

    # 在庫の行を FOR UPDATE で引くので、SELECT だけを開いても RLS の UPDATE のポリシーが他社の行を除き、scope の抜けが見えない
    # （docs/guides/testing.md「行列テストとの分担」）
    describe "RLS の SELECT と UPDATE を開いたとき" do
      include_context "RLS の SELECT と UPDATE を開く"

      it "他社の品目は NOT_FOUND で、他社の在庫を書かない" do
        Tenancy.with_tenant(supplier.id) do
          cross_read!
          # 対照：開いた後は、他社の在庫が見え、自社の在庫は変える
          before = reread(theirs)
          expect(described_class.set_safety_stock(actor, item_id: own.item_id, safety_stock: 12)).to be_success
          expect(own.reload.safety_stock).to eq(12)

          result = described_class.set_safety_stock(actor, item_id: theirs.item_id, safety_stock: 99)
          expect(failures(result)).to eq([ [ :not_found, [ :item_id ] ] ])
          expect(reread(theirs)).to eq(before)
        end
      end
    end

    it "在庫の行の無い品目は NOT_FOUND で、行を作らない" do
      item_id = SecureRandom.uuid

      expect(failures(set(item_id, 1))).to eq([ [ :not_found, [ :item_id ] ] ])
      expect(safety_stock_seen_by(supplier, item_id)).to be_nil
    end

    it "安全在庫は 0 と 2,147,483,647 ちょうどを受け付け、負と 2,147,483,648 と整数でない値は INVALID_INPUT で何も書かない" do
      expect([ -1, 2_147_483_648, 1.5, "3" ].map { failures(set(own.item_id, _1)) }).to all(eq([ [ :invalid_input, [ :safety_stock ] ] ]))
      expect(safety_stock_seen_by(supplier, own.item_id)).to eq(3)

      expect(set(own.item_id, 0)).to be_success
      expect(set(own.item_id, 2_147_483_647)).to be_success
      expect(safety_stock_seen_by(supplier, own.item_id)).to eq(2_147_483_647)
    end

    it "本番の環境では、DEMO_WORLD_ENABLED が無いか 1 でなければ何も書かずに例外にし、1 なら書く" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))

      [ nil, "true" ].each do |value|
        with_env("DEMO_WORLD_ENABLED" => value) { expect { set(own.item_id, 12) }.to raise_error(Inventory::Stocks::ProductionEnvironment) }
      end
      expect(safety_stock_seen_by(supplier, own.item_id)).to eq(3)

      with_env("DEMO_WORLD_ENABLED" => "1") { expect(set(own.item_id, 12)).to be_success }
      expect(safety_stock_seen_by(supplier, own.item_id)).to eq(12)
    end
  end

  # 一覧の並べ替えと絞り込み（docs/architecture/graphql-schema.md「ページングと N+1」）
  describe ".list" do
    def list(first: 2, **options)
      Tenancy.with_tenant(supplier.id) do
        values = []
        after = nil
        loop do
          page = described_class.list(actor, first:, after:, **options)
          values.concat(page.values)
          break [ values.map(&:item_id), page.total_count ] unless page.has_next_page

          after = page.cursors.last
        end
      end
    end

    it "並べ替えの列ごとに、列の値（有効在庫は現在庫 - 引当）と ID の組で並べる" do
      a, b, c, d = Tenancy.with_tenant(supplier.id) do
        [ [ 5, 0, 9 ], [ 8, 4, 2 ], [ 7, 1, 2 ], [ 6, 2, 1 ] ].map do |on_hand, allocated, safety_stock|
          FactoryBot.create(:stock, on_hand:, allocated:, safety_stock:)
        end
      end
      Tenancy.with_tenant(other.id) { FactoryBot.create(:stock) }

      expect(list(order_by: [ { field: :on_hand, direction: :asc } ])).to eq([ [ a, d, c, b ].map(&:item_id), 4 ])
      expect(list(order_by: [ { field: :allocated, direction: :desc } ])).to eq([ [ b, d, c, a ].map(&:item_id), 4 ])
      expect(list(order_by: [ { field: :available, direction: :desc } ])).to eq([ [ c, a, d, b ].map(&:item_id), 4 ])
      expect(list(order_by: [ { field: :safety_stock, direction: :asc } ])).to eq([ [ d, b, c, a ].map(&:item_id), 4 ])
    end

    # 品目のコードと名前は品目の写しで並べ、絞る。写しの無い在庫は、並べると向きによらず最後に置き、検索には当たらない
    describe "品目の写し" do
      # code と name の写しを持つ在庫。code が nil なら写しを作らない
      def labeled_stock(code, name = "#{code} の品目", **stock)
        Tenancy.with_tenant(supplier.id) do
          FactoryBot.create(:stock, **stock).tap { FactoryBot.create(:item_label, item_id: _1.item_id, code:, name:) if code }
        end
      end

      # 品目名は列の照合順序 ja-x-icu で、漢字を音読みの順（平のヘイが六のロクより前）に並べる
      it "品目コードと品目名と ID の組で並べ、写しの無い在庫は向きによらず最後に置く" do
        bolt = labeled_stock("B-1", "六角ボルト")
        unlabeled = labeled_stock(nil)
        nut = labeled_stock("N-2", "六角ナット")
        washer = labeled_stock("W-3", "平座金")

        expect(list(order_by: [ { field: :item_code, direction: :asc } ])).to eq([ [ bolt, nut, washer, unlabeled ].map(&:item_id), 4 ])
        expect(list(order_by: [ { field: :item_code, direction: :desc } ])).to eq([ [ washer, nut, bolt, unlabeled ].map(&:item_id), 4 ])
        expect(list(order_by: [ { field: :item_name, direction: :asc } ])).to eq([ [ washer, nut, bolt, unlabeled ].map(&:item_id), 4 ])
      end

      it "keyword は写しの品目コードか品目名に含む在庫に絞り、件数も同じ条件で数える。写しの無い在庫は当たらない" do
        bolt = labeled_stock("B-1", "六角ボルト")
        nut = labeled_stock("n-2", "六角ナット")
        labeled_stock("W-3", "平座金")
        labeled_stock(nil)

        expect(list(filter: { keyword: "　六角 " })).to eq([ [ nut, bolt ].map(&:item_id), 2 ])
        expect(list(filter: { keyword: "N-2" })).to eq([ [ nut.item_id ], 1 ])
        expect(list(filter: { keyword: "" })[1]).to eq(4)
      end

      it "keyword の % と _ は、ワイルドカードではなく文字として扱う" do
        off = labeled_stock("50%OFF")
        under = labeled_stock("A_1")
        labeled_stock("500FF")
        labeled_stock("AB1")

        expect(list(filter: { keyword: "%" })).to eq([ [ off.item_id ], 1 ])
        expect(list(filter: { keyword: "_" })).to eq([ [ under.item_id ], 1 ])
        # 対照：ワイルドカードでない文字は、そのまま部分一致で絞る
        expect(list(filter: { keyword: "0" })[1]).to eq(2)
      end

      it "keyword と belowSafetyStock を同時に渡せば、両方に当たる在庫に絞る" do
        below = labeled_stock("B-1", safety_stock: 20)
        labeled_stock("B-2")
        labeled_stock("N-1", safety_stock: 20)

        expect(list(filter: { keyword: "B-", below_safety_stock: true })).to eq([ [ below.item_id ], 1 ])
      end
    end

    # 集計と、そこから飛ぶ一覧が同じ条件で絞ることを、同じ在庫で両方を読んで確かめる
    it "belowSafetyStock は、ダッシュボードの安全在庫と同じ在庫に絞り、件数も同じ。偽か省けば絞らない" do
      Tenancy.with_tenant(supplier.id) do
        [ [ 4, 0, 5 ], [ 5, 0, 5 ], [ 6, 0, 5 ], [ 10, 6, 5 ], [ 10, 5, 5 ] ].each do |on_hand, allocated, safety_stock|
          FactoryBot.create(:stock, on_hand:, allocated:, safety_stock:)
        end
      end
      Tenancy.with_tenant(other.id) { FactoryBot.create(:stock, on_hand: 0, safety_stock: 1) }
      below = below_safety_stock.map(&:item_id)

      expect(below.size).to eq(2)
      expect(list(filter: { below_safety_stock: true }).then { [ _1.sort, _2 ] }).to eq([ below.sort, below.size ])
      expect(list(filter: { below_safety_stock: false })[1]).to eq(5)
      expect(list[1]).to eq(5)
    end
  end

  describe ".movements" do
    def movements(**options)
      Tenancy.with_tenant(supplier.id) do
        page = described_class.movements(actor, first: 10, after: nil, **options)
        [ page.values.map(&:type), page.total_count ]
      end
    end

    it "移動の種類で絞り、件数も同じ条件で数える。空の配列は 0 件で、省くか nil なら絞らない" do
      item_id = Tenancy.with_tenant(supplier.id) do
        FactoryBot.create(:stock).item_id.tap do |id|
          %w[inbound outbound inbound].each { FactoryBot.create(:stock_movement, item_id: id, type: _1) }
          FactoryBot.create(:stock_movement, type: "outbound")
        end
      end
      Tenancy.with_tenant(other.id) { FactoryBot.create(:stock_movement, type: "inbound") }

      expect(movements(filter: { types: %w[inbound] })).to eq([ %w[inbound inbound], 2 ])
      expect(movements(item_id:, filter: { types: %w[outbound] })).to eq([ %w[outbound], 1 ])
      expect(movements(filter: { types: %w[inbound outbound] })[1]).to eq(4)
      expect(movements(filter: { types: [] })).to eq([ [], 0 ])
      expect(movements(filter: { types: nil })[1]).to eq(4)
      expect(movements[1]).to eq(4)
    end
  end
end
