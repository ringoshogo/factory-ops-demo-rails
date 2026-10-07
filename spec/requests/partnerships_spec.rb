require "rails_helper"

# 取引関係の GraphQL の入口（docs/implementation-plan.md M8 の完了条件、docs/architecture/graphql-schema.md「ID と node」「役割による制限」）
RSpec.describe "取引関係の GraphQL", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:supplier_admin) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) } }
  let(:supplier_member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:buyer_admin) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user, :admin) } }
  let(:partnership) do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[view_catalog]) }
  end

  def login_as(user)
    post "/session", params: { email: user.email, password: "password" }, as: :json
    expect(response).to have_http_status(:no_content)
  end

  def graphql(query, **variables)
    post "/graphql", params: { query:, variables: }, as: :json
    response.parsed_body
  end

  def mutate(name, input)
    graphql(<<~GRAPHQL, input:).fetch("data").fetch(name)
      mutation($input: #{name.camelize}Input!) {
        #{name}(input: $input) { partnership { id status permissions buyer { name } } errors { code message path } }
      }
    GRAPHQL
  end

  def partnerships_of_supplier
    actor = Tenancy.with_tenant(supplier.id) { Partnerships::Authentication.actor(supplier_admin.id) }
    Tenancy.with_tenant(supplier.id) { Partnerships::Directory.for_supplier(actor) }
  end

  def error_codes(body) = body["errors"].map { _1.dig("extensions", "code") }

  describe "establishPartnership" do
    before { login_as(supplier_admin) }

    it "取引用コードで結び、相手の名前を返す" do
      result = mutate("establishPartnership", partnerCode: buyer.partner_code)

      expect(result).to match("partnership" => include("status" => "ACTIVE", "buyer" => { "name" => buyer.name }), "errors" => [])
    end

    # 応答がまったく同じなので、テナントの code が実在するかどうかを推測できない
    it "存在しない取引用コードとテナントの code の指定に、同じ NOT_FOUND を返す" do
      not_found = { "partnership" => nil, "errors" => [ { "code" => "NOT_FOUND", "message" => "Not found", "path" => [ "partnerCode" ] } ] }

      expect(mutate("establishPartnership", partnerCode: "no-such-code")).to eq(not_found)
      expect(mutate("establishPartnership", partnerCode: buyer.code)).to eq(not_found)
    end
  end

  describe "役割による制限" do
    before { login_as(supplier_member) }

    {
      "establishPartnership" => ->(spec) { { partnerCode: spec.buyer.partner_code } },
      "revokePartnership" => ->(spec) { { partnershipId: spec.partnership.id } },
      "grantPermission" => ->(spec) { { partnershipId: spec.partnership.id, permission: "PLACE_ORDERS" } },
      "withdrawPermission" => ->(spec) { { partnershipId: spec.partnership.id, permission: "VIEW_CATALOG" } }
    }.each do |name, input|
      it "member の #{name} は FORBIDDEN で、何も変わらない" do
        variables = input.call(self)
        before = partnerships_of_supplier
        body = graphql("mutation($input: #{name.camelize}Input!) { #{name}(input: $input) { errors { code } } }", input: variables)

        expect(body["data"]).to eq(name => nil)
        expect(error_codes(body)).to eq([ "FORBIDDEN" ])
        expect(partnerships_of_supplier).to eq(before)
      end
    end

    it "member も一覧は読める" do
      partnership
      expect(graphql("{ supplier { partnerships { id } } }").dig("data", "supplier", "partnerships")).to eq([ { "id" => partnership.id } ])
    end
  end

  describe "失効" do
    it "受注側の admin が失効させると、発注側の経路 2 と権限の判定が閉じる" do
      partnership
      login_as(buyer_admin)
      expect(graphql("{ buyer { suppliers { supplier { name } permissions } } }").dig("data", "buyer", "suppliers"))
        .to eq([ { "supplier" => { "name" => supplier.name }, "permissions" => [ "VIEW_CATALOG" ] } ])

      login_as(supplier_admin)
      expect(mutate("revokePartnership", partnershipId: partnership.id)).to match("partnership" => include("status" => "REVOKED"), "errors" => [])

      login_as(buyer_admin)
      expect(graphql("{ buyer { suppliers { supplier { name } } } }").dig("data", "buyer", "suppliers")).to eq([])
      buyer_actor = Tenancy.with_tenant(buyer.id) { Partnerships::Authentication.actor(buyer_admin.id) }
      expect(Tenancy.with_tenant(buyer.id) do
        Partnerships::Access.permitted?(buyer_actor, supplier_tenant_id: supplier.id, permission: "view_catalog")
      end).to be(false)
    end

    # 存在しない ID と同じ応答なので、相手の関係の ID が実在するかどうかを推測できない
    it "発注側の admin は、相手が結んだ関係を失効させられず、存在しない ID と同じ NOT_FOUND を返す" do
      login_as(buyer_admin)
      not_found = { "partnership" => nil, "errors" => [ { "code" => "NOT_FOUND", "message" => "Not found", "path" => nil } ] }

      expect(mutate("revokePartnership", partnershipId: partnership.id)).to eq(not_found)
      expect(mutate("revokePartnership", partnershipId: SecureRandom.uuid)).to eq(not_found)
      expect(partnerships_of_supplier.map(&:status)).to eq(%w[active])
    end
  end

  describe "viewer.partnerCode" do
    it "admin には自社の取引用コードを返し、member には返さない" do
      login_as(supplier_admin)
      expect(graphql("{ viewer { partnerCode } }").dig("data", "viewer", "partnerCode")).to eq(supplier.partner_code)

      login_as(supplier_member)
      expect(graphql("{ viewer { partnerCode } }").dig("data", "viewer", "partnerCode")).to be_nil
    end
  end
end
