require "rails_helper"

# 在庫と引当の入口。入庫と引当が受注の状況・在庫・移動履歴に現れ、有効在庫を超える出庫は入力の誤りになる
# （docs/architecture/graphql-schema.md「mutation の一覧」、docs/architecture/data-model.md「在庫（`inventory`）」）
RSpec.describe "在庫と引当", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code: "BOLT-8") } }
  let!(:order) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:sales_order).tap { FactoryBot.create(:sales_order_line, :matched, sales_order: _1, item_id: item.id, quantity: 5) }
    end
  end

  before { login_as(member) }

  def adjust(type, quantity, item_id: item.id)
    graphql_body(<<~GRAPHQL, input: { itemId: item_id, type:, quantity:, reason: "棚卸" }).dig("data", "adjustStock")
      mutation($input: AdjustStockInput!) {
        adjustStock(input: $input) { stock { item { code } onHand allocated available } errors { code path } }
      }
    GRAPHQL
  end

  def allocate
    graphql_body(<<~GRAPHQL, input: { salesOrderId: order.id }).dig("data", "allocateSalesOrder")
      mutation($input: AllocateSalesOrderInput!) {
        allocateSalesOrder(input: $input) { salesOrder { status lines { allocatedQuantity } } errors { code } }
      }
    GRAPHQL
  end

  it "入庫して引き当てると、受注の状況・明細の引当数量・品目の在庫・移動履歴に現れる" do
    expect(adjust("INBOUND", 3)).to eq("stock" => { "item" => { "code" => "BOLT-8" }, "onHand" => 3, "allocated" => 0,
      "available" => 3 }, "errors" => [])
    expect(allocate).to eq("salesOrder" => { "status" => "PARTIALLY_ALLOCATED", "lines" => [ { "allocatedQuantity" => 3 } ] },
      "errors" => [])

    adjust("INBOUND", 2)
    expect(allocate.dig("salesOrder", "status")).to eq("ALLOCATED")

    expect(graphql_body("{ supplier { items { nodes { stock { onHand allocated available belowSafetyStock } } } } }")
      .dig("data", "supplier", "items", "nodes")).to eq([ { "stock" => { "onHand" => 5, "allocated" => 5, "available" => 0,
        "belowSafetyStock" => false } } ])
    expect(graphql_body("query($id: ID) { supplier { stockMovements(itemId: $id) { nodes { type quantity reason } } } }", id: item.id)
      .dig("data", "supplier", "stockMovements", "nodes").map(&:values))
      .to eq([ [ "ALLOCATE", 2, nil ], [ "INBOUND", 2, "棚卸" ], [ "ALLOCATE", 3, nil ], [ "INBOUND", 3, "棚卸" ] ])
  end

  it "有効在庫を超える出庫は INVALID_INPUT、見えない品目は NOT_FOUND を返す" do
    adjust("INBOUND", 5)
    allocate

    expect(adjust("OUTBOUND", 1)).to eq("stock" => nil, "errors" => [ { "code" => "INVALID_INPUT", "path" => [ "quantity" ] } ])
    expect(adjust("INBOUND", 1, item_id: SecureRandom.uuid)).to eq("stock" => nil, "errors" => [ { "code" => "NOT_FOUND", "path" => nil } ])
  end

  it "入出庫も引当もしていない品目の在庫は空" do
    expect(graphql_body("{ supplier { items { nodes { stock { onHand } } } } }").dig("data", "supplier", "items", "nodes"))
      .to eq([ { "stock" => nil } ])
  end

  # 在庫の一覧の品目の検索と並べ替えは、saveItem が在庫へ写した品目のコードと名前を読む
  # （docs/architecture/graphql-schema.md「ページングと N+1」、docs/architecture/data-model.md「在庫（`inventory`）」）
  describe "品目のコードと名前での検索と並べ替え" do
    let(:stocks_query) do
      <<~GRAPHQL
        query($orderBy: StockOrder, $filter: StockFilter) {
          supplier { stocks(orderBy: $orderBy, filter: $filter) { totalCount nodes { item { code } } } }
        }
      GRAPHQL
    end

    def save_item(code, name)
      graphql_body(<<~GRAPHQL, input: { code:, name:, unit: "個", unitPrice: 100 }).dig("data", "saveItem", "item", "id")
        mutation($input: SaveItemInput!) { saveItem(input: $input) { item { id } errors { code } } }
      GRAPHQL
    end

    def stocks(**variables)
      graphql_body(stocks_query, **variables).dig("data", "supplier", "stocks")&.then { [ _1["nodes"]&.map { |node| node.dig("item", "code") }, _1["totalCount"] ] }
    end

    before do
      { "N-2" => "六角ナット M8", "B-1" => "六角ボルト M8", "W-3" => "平座金 M8" }.each do |code, name|
        adjust("INBOUND", 1, item_id: save_item(code, name))
      end
    end

    it "keyword は品目コードか品目名に含む在庫に絞り、件数も同じ条件で数える" do
      # 対照：絞らなければ 3 件とも返る（在庫の作った順の新しいものから）
      expect(stocks).to eq([ %w[W-3 B-1 N-2], 3 ])
      expect(stocks(filter: { keyword: "六角" })).to eq([ %w[B-1 N-2], 2 ])
      expect(stocks(filter: { keyword: "w-3" })).to eq([ %w[W-3], 1 ])
    end

    it "keyword は品目の一覧と同じく 100 文字ちょうどを受け付け、101 文字はトップレベルのエラーにする" do
      query = "query($keyword: String) { supplier { stocks(filter: { keyword: $keyword }) { totalCount } } }"

      expect(graphql_body(query, keyword: "あ" * 100)).to eq("data" => { "supplier" => { "stocks" => { "totalCount" => 0 } } })
      expect(graphql_body(query, keyword: "あ" * 101)["errors"].map { _1["message"] }).to eq([ "keyword is too long (maximum is 100)" ])
    end

    # 品目名の列の照合順序 ja-x-icu は、漢字を音読みの順（平のヘイが六のロクより前）で並べ、流用元の Intl.Collator("ja") と
    # 同じ並びになる。コードポイントの順では六角の 2 つが先になる
    it "品目コードと品目名で並べる" do
      expect(stocks(orderBy: { field: "ITEM_CODE", direction: "ASC" })).to eq([ %w[B-1 N-2 W-3], 3 ])
      expect(stocks(orderBy: { field: "ITEM_NAME", direction: "ASC" })).to eq([ %w[W-3 N-2 B-1], 3 ])
    end

    it "品目名を、漢字の音読みの順に 1 件ずつのページで並べ、ページの境目で抜けも重なりもしない" do
      query = <<~GRAPHQL
        query($after: String) {
          supplier { stocks(first: 1, after: $after, orderBy: { field: ITEM_NAME, direction: ASC }) {
            nodes { item { code } } pageInfo { hasNextPage endCursor }
          } }
        }
      GRAPHQL
      codes = []
      after = nil
      loop do
        page = graphql_body(query, after:).dig("data", "supplier", "stocks")
        codes.concat(page.fetch("nodes").map { _1.dig("item", "code") })
        break unless page.dig("pageInfo", "hasNextPage")

        after = page.dig("pageInfo", "endCursor")
      end

      expect(codes).to eq(%w[W-3 N-2 B-1])
    end

    # 品目コードの列（pg_c_utf8）は ASCII の外の文字も、品目名の列（ja-x-icu）は全角の英字も、大文字と小文字を区別せずに探す。
    # 全角と半角は別の文字として扱う
    it "keyword は、ASCII の外の文字と全角の英字の大文字と小文字を区別せず、全角と半角は区別する" do
      { "Ä-4" => "ＡＢＣ継手", "Ö-5" => "abc 継手" }.each { |code, name| adjust("INBOUND", 1, item_id: save_item(code, name)) }

      expect(stocks(filter: { keyword: "ä-" })).to eq([ %w[Ä-4], 1 ])
      expect(stocks(filter: { keyword: "ａｂｃ" })).to eq([ %w[Ä-4], 1 ])
      expect(stocks(filter: { keyword: "ABC" })).to eq([ %w[Ö-5], 1 ])
    end
  end
end
