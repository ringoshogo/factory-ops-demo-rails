require "rails_helper"
require_relative "../support/matrix_world"
require_relative "graphql_expectations"

# 入口のフィールドと mutation ごとに、ペルソナとしてログインして実行し、結果の種類を確かめる
# （docs/architecture/context-map.md「テナントと所有」、docs/architecture/graphql-schema.md「エラー」）
RSpec.describe "入口の行列", type: :request do
  let(:world) { MatrixWorld.new }

  # 型ごとの、応答の data からフィールドの親までの道
  def parent_paths = { "BuyerView" => %w[buyer], "SupplierView" => %w[supplier], "Query" => [], "Mutation" => [] }

  # 視点の入口そのもの（Query.buyer・Query.supplier）は、データを持たないので除く
  def schema_entries
    parent_paths.keys.filter_map { |name| FactoryOpsSchema.get_type(name) }.flat_map do |type|
      type.fields.values.reject { |field| field.type.unwrap.graphql_name.in?(%w[BuyerView SupplierView]) }
        .map { |field| "#{type.graphql_name}.#{field.graphql_name}" }
    end
  end

  def outcome(body, path)
    return :forbidden if body["errors"]&.any? { |error| error.dig("extensions", "code") == "FORBIDDEN" }
    raise "想定外のエラー: #{body['errors']}" if body["errors"].present?

    value = body.dig("data", *path)
    return :null if value.nil?
    return value["errors"].first["code"].downcase.to_sym if value.is_a?(Hash) && value["errors"].present?

    list = value.is_a?(Hash) ? value["nodes"] || value["edges"] : value
    list.is_a?(Array) && list.empty? ? :empty : :value
  end

  it "入口のフィールドと mutation すべてに期待値があり、無いフィールドの期待値は無い" do
    expect(MatrixExpectations::GRAPHQL.keys).to match_array(schema_entries)
  end

  it "期待値はすべてのペルソナについて、決めた結果の種類で書かれている" do
    MatrixExpectations::GRAPHQL.each do |key, entry|
      expect(entry[:expect].keys).to match_array(MatrixWorld::PERSONAS), key
      expect(entry[:expect].values - MatrixExpectations::OUTCOMES).to be_empty, key
    end
  end

  MatrixExpectations::GRAPHQL.each do |key, entry|
    type_name, field_name = key.split(".")

    describe key do
      MatrixWorld::PERSONAS.each do |persona|
        it "#{persona} には #{entry[:expect][persona]}" do
          post "/session", params: { email: world.users[persona].email, password: "password" }, as: :json
          expect(response).to have_http_status(:no_content)

          post "/graphql", params: { query: entry[:query], variables: entry[:variables]&.call(world) || {} }, as: :json

          expect(outcome(response.parsed_body, [ *parent_paths.fetch(type_name), field_name ])).to eq(entry[:expect][persona])
        end
      end
    end
  end
end
