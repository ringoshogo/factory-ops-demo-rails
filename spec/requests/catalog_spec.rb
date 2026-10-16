require "rails_helper"

# カタログの GraphQL の入口。発注側は経路 1 で取引先の公開品目だけを読み、受注側の一覧には自社の品目だけが出る
# （docs/architecture/graphql-schema.md「発注側の視点」「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
RSpec.describe "カタログの GraphQL", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:supplier_member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }
  let!(:partnership) do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[view_catalog]) }
  end
  let!(:published) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, :published, code: "B-1") } }
  let!(:unpublished) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code: "A-1") } }

  def mutate(name, input)
    graphql_body(<<~GRAPHQL, input:).fetch("data").fetch(name)
      mutation($input: #{name.camelize}Input!) {
        #{name}(input: $input) { item { id code name unitPrice taxRatePercent published } errors { code message path } }
      }
    GRAPHQL
  end

  def catalog_codes
    graphql_body("{ buyer { suppliers { catalog { nodes { code } } } } }")
      .dig("data", "buyer", "suppliers").flat_map { _1.dig("catalog", "nodes") }.map { _1["code"] }
  end

  def change_grant(name)
    Tenancy.with_tenant(supplier.id) do
      actor = Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "admin", partner_code: "")
      Partnerships::Management.public_send(name, actor, partnership_id: partnership.id, permission: "view_catalog")
    end
  end

  describe "経路 1（SupplierPartnership.catalog）" do
    before { login_as(buyer_member) }

    it "公開品目だけを返し、品目 ID をフィールドにもカーソルにも出さない" do
      body = graphql_body("{ buyer { suppliers { catalog { edges { cursor node { code name unit unitPrice taxRatePercent } } } } } }")

      expect(body.dig("data", "buyer", "suppliers", 0, "catalog", "edges")).to eq([
        { "cursor" => "B-1", "node" => { "code" => "B-1", "name" => published.name, "unit" => "個", "unitPrice" => "120",
          "taxRatePercent" => 10 } }
      ])
      expect(response.body).not_to include(published.id)
      expect(Types::PublishedCatalogItemType.fields.keys).not_to include("id")
    end

    it "品目の数によらず、1 ページを読むクエリの数は変わらない" do
      query_count = lambda do
        count = 0
        callback = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { catalog_codes }
        count
      end

      one_item = query_count.call
      Tenancy.with_tenant(supplier.id) { 4.times { FactoryBot.create(:item, :published, code: "C-#{_1}") } }
      five_items = query_count.call

      expect(catalog_codes.size).to eq(5)
      expect(five_items).to eq(one_item)
    end

    it "view_catalog を撤回すると空になり、付与し直すと開く" do
      change_grant(:withdraw)
      expect(catalog_codes).to eq([])

      change_grant(:grant)
      expect(catalog_codes).to eq(%w[B-1])
    end

    it "公開した品目が現れ、非公開に戻すと消える" do
      login_as(supplier_member)
      expect(mutate("setItemPublished", itemId: unpublished.id, published: true)).to include("errors" => [])

      login_as(buyer_member)
      expect(catalog_codes).to eq(%w[A-1 B-1])

      login_as(supplier_member)
      mutate("setItemPublished", itemId: published.id, published: false)

      login_as(buyer_member)
      expect(catalog_codes).to eq(%w[A-1])
    end

    it "品目コードの順に、カーソルの後から続きを返す" do
      Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, :published, code: "C-1") }
      query = "query($after: String) { buyer { suppliers { catalog(first: 1, after: $after) { nodes { code } pageInfo { hasNextPage endCursor } } } } }"

      first = graphql_body(query).dig("data", "buyer", "suppliers", 0, "catalog")
      expect(first).to eq("nodes" => [ { "code" => "B-1" } ], "pageInfo" => { "hasNextPage" => true, "endCursor" => "B-1" })

      second = graphql_body(query, after: "B-1").dig("data", "buyer", "suppliers", 0, "catalog")
      expect(second).to eq("nodes" => [ { "code" => "C-1" } ], "pageInfo" => { "hasNextPage" => false, "endCursor" => "C-1" })
    end
  end

  describe "supplier.items" do
    # 発注側のテナントは RLS で取引先の公開品目も読めるので、scope が所有の条件を明示していなければ混ざる
    it "取引先の公開品目が見えるテナントでも、自社の品目だけを返す" do
      own = Tenancy.with_tenant(buyer.id) { FactoryBot.create(:item) }
      login_as(buyer_member)

      expect(graphql_body("{ supplier { items { nodes { id } } } }").dig("data", "supplier", "items", "nodes")).to eq([ { "id" => own.id } ])
      expect(catalog_codes).to eq(%w[B-1])
    end

    it "作成順の新しいものから、カーソルの後から続きを返す" do
      login_as(supplier_member)
      query = "query($after: String) { supplier { items(first: 1, after: $after) { nodes { id } pageInfo { hasNextPage endCursor } } } }"

      first = graphql_body(query).dig("data", "supplier", "items")
      expect(first).to eq("nodes" => [ { "id" => unpublished.id } ], "pageInfo" => { "hasNextPage" => true, "endCursor" => unpublished.id })

      second = graphql_body(query, after: unpublished.id).dig("data", "supplier", "items")
      expect(second).to eq("nodes" => [ { "id" => published.id } ], "pageInfo" => { "hasNextPage" => false, "endCursor" => published.id })
    end

    it "形の誤ったカーソルはトップレベルのエラーにする" do
      login_as(supplier_member)

      expect(graphql_body("{ supplier { items(after: \"x\") { nodes { id } } } }")["errors"].map { _1["message"] }).to eq([ "Invalid cursor" ])
    end

    it "orderBy の列と向きで並べ、そのカーソルで続きを返し、件数を返す。向きを変えたカーソルはトップレベルのエラーにする" do
      login_as(supplier_member)
      query = <<~GRAPHQL
        query($after: String, $direction: OrderDirection!) {
          supplier { items(first: 1, after: $after, orderBy: { field: CODE, direction: $direction }) { totalCount nodes { code } pageInfo { endCursor } } }
        }
      GRAPHQL

      first = graphql_body(query, direction: "ASC").dig("data", "supplier", "items")
      expect(first.slice("totalCount", "nodes")).to eq("totalCount" => 2, "nodes" => [ { "code" => "A-1" } ])
      after = first.dig("pageInfo", "endCursor")
      expect(graphql_body(query, direction: "ASC", after:).dig("data", "supplier", "items", "nodes")).to eq([ { "code" => "B-1" } ])
      expect(graphql_body(query, direction: "DESC", after:)["errors"].map { _1["message"] }).to eq([ "Invalid cursor" ])
    end

    # thenBy が無ければ、名前の同じ品目は主キーの順（作った順）に並び、コードの降順と食い違う
    it "orderBy の列の値が同じ行を thenBy の列で並べ、そのカーソルで続きを返す" do
      %w[N-1 N-2].each { |code| Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code:, name: "六角ナット") } }
      login_as(supplier_member)
      query = <<~GRAPHQL
        query($after: String) {
          supplier { items(first: 1, after: $after, orderBy: { field: NAME, direction: ASC }, thenBy: [{ field: CODE, direction: DESC }],
            filter: { keyword: "六角ナット" }) { nodes { code } pageInfo { hasNextPage endCursor } } }
        }
      GRAPHQL

      first = graphql_body(query).dig("data", "supplier", "items")
      expect(first&.fetch("nodes")).to eq([ { "code" => "N-2" } ])
      second = graphql_body(query, after: first.dig("pageInfo", "endCursor")).dig("data", "supplier", "items")
      expect(second.fetch("nodes")).to eq([ { "code" => "N-1" } ])
      expect(second.dig("pageInfo", "hasNextPage")).to be(false)
    end

    # 1 件ずつのページで最後までたどった品目コード。ページの境目ごとに、その並べ替えのカーソルで続きを読む。
    # 並べ替えを受け付けなければ、data が無く nil を返す
    def item_codes(order)
      query = <<~GRAPHQL
        query($after: String, $orderBy: ItemOrder, $thenBy: [ItemOrder!]) {
          supplier { items(first: 1, after: $after, orderBy: $orderBy, thenBy: $thenBy) { nodes { code } pageInfo { hasNextPage endCursor } } }
        }
      GRAPHQL
      codes = []
      after = nil
      loop do
        page = graphql_body(query, after:, **order).dig("data", "supplier", "items")
        break unless page

        codes.concat(page.fetch("nodes").map { _1["code"] })
        break codes unless page.dig("pageInfo", "hasNextPage")

        after = page.dig("pageInfo", "endCursor")
      end
    end

    # 安全在庫は在庫のパッケージの値で、在庫の行の無い品目（A-1）は空として、向きによらず最後に並ぶ
    it "orderBy の安全在庫で並べ、在庫の行の無い品目を最後に置き、そのカーソルで続きを返す" do
      Tenancy.with_tenant(supplier.id) do
        FactoryBot.create(:stock, item_id: published.id, safety_stock: 3)
        FactoryBot.create(:item, code: "C-1").tap { FactoryBot.create(:stock, item_id: _1.id, safety_stock: 8) }
      end
      login_as(supplier_member)

      expect(item_codes(orderBy: { field: "SAFETY_STOCK", direction: "DESC" })).to eq(%w[C-1 B-1 A-1])
      expect(item_codes(orderBy: { field: "SAFETY_STOCK", direction: "ASC" })).to eq(%w[B-1 C-1 A-1])
    end

    # 単価は今日の販売単価で並ぶ。単位の同じ品目（個）を単価の降順に並べ、単位の違う品目（箱）は後ろに来る
    it "orderBy の単位と thenBy の今日の単価で並べ、そのカーソルで続きを返す" do
      Tenancy.with_tenant(supplier.id) do
        FactoryBot.create(:item, code: "C-1", unit: "箱", unit_price: 50)
        FactoryBot.create(:item, code: "D-1", unit: "個", unit_price: 500)
        FactoryBot.create(:item, code: "E-1", unit: "個", unit_price: 80)
      end
      login_as(supplier_member)

      # A-1・B-1 は単位が個で、単価が既定の 120
      expect(item_codes(orderBy: { field: "UNIT", direction: "ASC" }, thenBy: [ { field: "UNIT_PRICE", direction: "DESC" } ]))
        .to eq(%w[D-1 A-1 B-1 E-1 C-1])
    end

    it "orderBy を省いた空でない thenBy と、同じ field を 2 回書いた並べ替えをトップレベルのエラーにする" do
      login_as(supplier_member)
      query = "query($orderBy: ItemOrder, $thenBy: [ItemOrder!]) { supplier { items(orderBy: $orderBy, thenBy: $thenBy) { totalCount } } }"
      code = { field: "CODE", direction: "ASC" }
      messages = ->(variables) { graphql_body(query, **variables)["errors"]&.map { _1["message"] } }

      expect(messages.call(thenBy: [ code ])).to eq([ "thenBy requires orderBy" ])
      expect(messages.call(orderBy: code, thenBy: [ { field: "CODE", direction: "DESC" } ])).to eq([ "orderBy and thenBy repeat a field" ])
      # 対照：orderBy があり、別の列なら通る
      expect(graphql_body(query, orderBy: code, thenBy: [ { field: "NAME", direction: "DESC" } ]))
        .to eq("data" => { "supplier" => { "items" => { "totalCount" => 2 } } })
    end

    # 画面（frontend/lib/list.ts）は空の thenBy を送らないが、API は空の配列を省いたときと同じに扱い、エラーにするのは
    # orderBy を省いて空でない thenBy を渡したときだけにする（docs/architecture/graphql-schema.md「ページングと N+1」）
    it "orderBy を省くと、thenBy を省いても空の配列にしても同じ一覧を返し、空でない thenBy だけをトップレベルのエラーにする" do
      login_as(supplier_member)
      query = "query($thenBy: [ItemOrder!]) { supplier { items(thenBy: $thenBy) { nodes { code } totalCount } } }"
      omitted = graphql_body(query)

      expect(omitted).to eq("data" => { "supplier" => { "items" => { "nodes" => [ { "code" => "A-1" }, { "code" => "B-1" } ], "totalCount" => 2 } } })
      expect(graphql_body(query, thenBy: [])).to eq(omitted)
      expect(graphql_body(query, thenBy: [ { field: "CODE", direction: "ASC" } ])["errors"]&.map { _1["message"] })
        .to eq([ "thenBy requires orderBy" ])
    end

    it "keyword は 100 文字ちょうどを受け付け、101 文字はトップレベルのエラーにする" do
      login_as(supplier_member)
      query = "query($keyword: String) { supplier { items(filter: { keyword: $keyword }) { totalCount } } }"

      expect(graphql_body(query, keyword: "あ" * 100)).to eq("data" => { "supplier" => { "items" => { "totalCount" => 0 } } })
      expect(graphql_body(query, keyword: "あ" * 101)["errors"].map { _1["message"] }).to eq([ "keyword is too long (maximum is 100)" ])
    end
  end

  # 見えない ID は S1（spec/scenarios/tenant_boundary_spec.rb）と入口の行列が確かめる
  describe "supplier.item" do
    it "自社の品目を ID で 1 件返す" do
      login_as(supplier_member)

      expect(graphql_body("query($id: ID!) { supplier { item(id: $id) { code } } }", id: unpublished.id).dig("data", "supplier", "item"))
        .to eq("code" => "A-1")
    end
  end

  # 同じコードの更新・公開の状態・入力の誤りの分岐は Sales::Catalog の spec が確かめる
  describe "saveItem" do
    before { login_as(supplier_member) }

    it "新しいコードなら非公開で作る" do
      created = mutate("saveItem", code: "N-1", name: "新品目", unit: "個", unitPrice: 300)

      expect(created).to match("item" => include("code" => "N-1", "unitPrice" => "300", "taxRatePercent" => 10, "published" => false),
        "errors" => [])
    end

    # 単価の列は bigint。上限を超える値は、トップレベルのエラーにせず、項目を指すユーザーエラーにする
    it "新しい品目の単価は bigint の最大値ちょうどを受け付け、最大値 + 1 は項目を指す INVALID_INPUT で作らない" do
      expect(mutate("saveItem", code: "N-2", name: "上限", unit: "個", unitPrice: "9223372036854775808"))
        .to match("item" => nil, "errors" => [ include("code" => "INVALID_INPUT", "path" => [ "unitPrice" ]) ])
      expect(mutate("saveItem", code: "N-1", name: "上限", unit: "個", unitPrice: "9223372036854775807"))
        .to match("item" => include("code" => "N-1", "unitPrice" => "9223372036854775807"), "errors" => [])
      codes = query("{ supplier { items { nodes { code } } } }").dig("supplier", "items", "nodes").pluck("code")
      expect(codes).to include("N-1")
      expect(codes).not_to include("N-2")
    end

    it "入力の誤りを、項目を指す INVALID_INPUT のユーザーエラーで返す" do
      expect(mutate("saveItem", code: "N-1", name: "x", unit: "個", unitPrice: 1, taxRatePercent: 5)["errors"])
        .to match([ include("code" => "INVALID_INPUT", "path" => [ "taxRatePercent" ]) ])
    end
  end
end
