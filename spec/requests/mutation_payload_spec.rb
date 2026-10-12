require "rails_helper"

# mutation の戻り値（payload）の null の伝わり方（docs/architecture/graphql-schema.md「mutation の一覧」「エラー」）。
# トップレベルのエラーがある要求は書き込みをすべて戻すので、成功の payload を返さず、data を null にする
RSpec.describe "mutation の戻り値の null", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }

  def save_item(code) = %(saveItem(input: { code: "#{code}", name: "品目", unit: "個", unitPrice: "100" }) { item { code } errors { code } })
  def item_codes = query("{ supplier { items { nodes { code } } } }").dig("supplier", "items", "nodes").pluck("code")

  before { login_as(member) }

  it "規則で拒否した mutation の null は、payload で止まらずに data まで伝わる" do
    body = graphql_body('mutation { establishPartnership(input: { partnerCode: "p-x" }) { errors { code } } }')

    expect(body.fetch("errors").map { _1.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
    expect(body).to include("data" => nil)
  end

  it "1 つの要求に並べた mutation の 1 つが規則で拒否されると、先に成功した mutation の payload も返さず、書き込みも戻る" do
    body = graphql_body(<<~GRAPHQL)
      mutation {
        first: #{save_item("PAYLOAD-1")}
        denied: establishPartnership(input: { partnerCode: "p-x" }) { errors { code } }
      }
    GRAPHQL

    expect(body.fetch("errors").map { _1.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
    expect(body).to include("data" => nil)
    expect(item_codes).not_to include("PAYLOAD-1")
  end

  it "ユーザーエラーだけの mutation は payload を返し、並べた成功の mutation の書き込みも残る" do
    body = graphql_body(<<~GRAPHQL)
      mutation {
        first: #{save_item("PAYLOAD-1")}
        invalid: saveItem(input: { code: "", name: "品目", unit: "個", unitPrice: "100" }) { item { code } errors { code } }
      }
    GRAPHQL

    expect(body).not_to have_key("errors")
    expect(body.fetch("data")).to eq("first" => { "item" => { "code" => "PAYLOAD-1" }, "errors" => [] },
      "invalid" => { "item" => nil, "errors" => [ { "code" => "INVALID_INPUT" } ] })
    expect(item_codes).to include("PAYLOAD-1")
  end
end
