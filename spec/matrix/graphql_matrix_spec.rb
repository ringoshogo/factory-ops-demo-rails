require "rails_helper"
require_relative "../support/matrix_world"
require_relative "graphql_expectations"

# 入口のフィールドと mutation ごとに、ペルソナとしてログインして実行し、結果の種類を確かめる
# （docs/architecture/context-map.md「テナントと所有」、docs/architecture/graphql-schema.md「エラー」）
RSpec.describe "入口の行列", type: :request do
  let(:world) { MatrixWorld.new }

  ROOTS = %w[BuyerView SupplierView Query Mutation].freeze

  # 型ごとの、応答の data からフィールドの親までの道。型の中の読む経路は、経路 2 の取引関係の一覧か発注の一覧の要素を親にする
  def parent_paths = { "BuyerView" => %w[buyer], "SupplierView" => %w[supplier], "Query" => [], "Mutation" => [],
    "SupplierPartnership" => %w[buyer suppliers], "PurchaseOrder" => %w[buyer purchaseOrders nodes] }

  # 相手テナントのデータを返す型。コネクションは中身の型で判定する
  def cross_tenant?(type)
    type = type.node_type if type.respond_to?(:node_type)
    type.try(:cross_tenant_read).present?
  end

  # 視点の入口と Mutation のフィールド、入口の下で相手側の型を返すフィールド（読む経路）。
  # 視点の入口そのもの（Query.buyer・Query.supplier）は、データを持たないので除く
  def schema_entries
    root_fields = ROOTS.filter_map { |name| FactoryOpsSchema.get_type(name) }.flat_map do |type|
      type.fields.values.reject { |field| field.type.unwrap.graphql_name.in?(%w[BuyerView SupplierView]) }
    end
    nested_fields = FactoryOpsSchema.types.values
      .select { |type| type.kind.object? && type < Types::BaseObject && !type.graphql_name.in?(ROOTS) }
      .reject { |type| type < Types::BaseConnection || type < Types::BaseEdge }
      .flat_map { |type| type.fields.values.select { |field| cross_tenant?(field.type.unwrap) } }

    (root_fields + nested_fields).map(&:path)
  end

  # 道の途中の一覧は要素ごとにたどり、たどり着いた値をすべて集める
  def dig_all(value, path)
    return [ value ] if path.empty?

    case value
    when Array then value.flat_map { dig_all(_1, path) }
    when Hash then dig_all(value[path.first], path.drop(1))
    else []
    end
  end

  def outcome(body, path)
    return :forbidden if body["errors"]&.any? { |error| error.dig("extensions", "code") == "FORBIDDEN" }
    raise "想定外のエラー: #{body['errors']}" if body["errors"].present?

    values = dig_all(body["data"], path)
    return :null if values == [ nil ]

    value = values.first
    return value["errors"].first["code"].downcase.to_sym if values.one? && value.is_a?(Hash) && value["errors"].present?

    lists = values.map { |each| each.is_a?(Hash) ? each["nodes"] || each["edges"] : each }
    lists.all?(Array) && lists.all?(&:empty?) ? :empty : :value
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
