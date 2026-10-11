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
  end

  # 同じコードの更新・公開の状態・入力の誤りの分岐は Sales::Catalog の spec が確かめる
  describe "saveItem" do
    before { login_as(supplier_member) }

    it "新しいコードなら非公開で作る" do
      created = mutate("saveItem", code: "N-1", name: "新品目", unit: "個", unitPrice: 300)

      expect(created).to match("item" => include("code" => "N-1", "unitPrice" => "300", "taxRatePercent" => 10, "published" => false),
        "errors" => [])
    end

    it "入力の誤りを、項目を指す INVALID_INPUT のユーザーエラーで返す" do
      expect(mutate("saveItem", code: "N-1", name: "x", unit: "個", unitPrice: 1, taxRatePercent: 5)["errors"])
        .to match([ include("code" => "INVALID_INPUT", "path" => [ "taxRatePercent" ]) ])
    end
  end
end
