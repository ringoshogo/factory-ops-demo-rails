require "rails_helper"
require_relative "../support/matrix_world"
require_relative "graphql_expectations"

# 入口のフィールドと mutation ごとに、ペルソナとしてログインして実行し、結果の種類を確かめる
# （docs/architecture/context-map.md「テナントと所有」、docs/architecture/graphql-schema.md「エラー」）。
# mutation は、値を返すペルソナの member でも呼び、admin に限る mutation が FORBIDDEN になって何も書かないことと、
# member に許す mutation が同じ値を返すことを確かめる（docs/architecture/graphql-schema.md「役割による制限」）
RSpec.describe "入口の行列", type: :request do
  MatrixWorld.share_per_file(self)

  ROOTS = %w[BuyerView SupplierView Query Mutation].freeze
  ROLES = %i[admin member].freeze

  # 型ごとの、応答の data からフィールドの親までの道。型の中の読む経路は、経路 2 の取引関係の一覧か発注の一覧の要素を親にする
  def parent_paths = { "BuyerView" => %w[buyer], "SupplierView" => %w[supplier], "Viewer" => %w[viewer], "Query" => [], "Mutation" => [],
    "SupplierPartnership" => %w[buyer suppliers], "PurchaseOrder" => %w[buyer purchaseOrders nodes] }

  # 相手テナントのデータを返す型。コネクションは中身の型で判定する
  def cross_tenant?(type)
    type = type.node_type if type.respond_to?(:node_type)
    type.try(:cross_tenant_read).present?
  end

  # 視点の入口と Mutation のフィールド、Viewer の下のリゾルバ、入口の下で相手側の型を返すフィールド（読む経路）。
  # 視点の入口そのもの（Query.buyer・Query.supplier）は、データを持たないので除く
  def schema_entries
    root_fields = ROOTS.filter_map { |name| FactoryOpsSchema.get_type(name) }.flat_map do |type|
      type.fields.values.reject { |field| field.type.unwrap.graphql_name.in?(%w[BuyerView SupplierView]) }
    end
    viewer_fields = FactoryOpsSchema.get_type("Viewer").fields.values.select(&:resolver)
    nested_fields = FactoryOpsSchema.types.values
      .select { |type| type.kind.object? && type < Types::BaseObject && !type.graphql_name.in?(ROOTS) }
      .reject { |type| type < Types::BaseConnection || type < Types::BaseEdge }
      .flat_map { |type| type.fields.values.select { |field| cross_tenant?(field.type.unwrap) } }

    (root_fields + viewer_fields + nested_fields).map(&:path)
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

  # ペルソナのテナントが所有する、テナントの表ごとの行数。監査の行も含む
  def owned_row_counts(persona)
    tenant_id = world.tenants.fetch(persona)
    world.as(persona) do
      MatrixWorld.tenant_tables.index_with do |table|
        connection = ActiveRecord::Base.lease_connection
        connection.select_value("SELECT count(*) FROM #{connection.quote_table_name(table)} WHERE owner_tenant_id = $1", "Matrix", [ tenant_id ])
      end
    end
  end

  def call(entry, user)
    variables = entry[:variables]&.call(world) || {}
    login_as(user)
    post "/graphql", params: { query: entry[:query], variables: }, as: :json
    response.parsed_body
  end

  it "mutation の行はすべて、許す役割を持つ。ほかの行は役割を持たない" do
    MatrixExpectations::GRAPHQL.each do |key, entry|
      if key.start_with?("Mutation.")
        expect(ROLES).to include(entry[:role]), "#{key} に role: :admin か role: :member を書く"
      else
        expect(entry).not_to have_key(:role), key
      end
    end
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
          login_as(world.users[persona])
          post "/graphql", params: { query: entry[:query], variables: entry[:variables]&.call(world) || {} }, as: :json

          expect(outcome(response.parsed_body, [ *parent_paths.fetch(type_name), field_name ])).to eq(entry[:expect][persona])
        end
      end

      entry[:expect].select { |_, result| result == :value }.each_key do |persona|
        case entry[:role]
        when :admin
          it "#{persona} の member には forbidden で、そのテナントの表に何も書かない" do
            variables = entry[:variables]&.call(world) || {}
            before = owned_row_counts(persona)
            login_as(world.members[persona])
            post "/graphql", params: { query: entry[:query], variables: }, as: :json

            expect(outcome(response.parsed_body, [ *parent_paths.fetch(type_name), field_name ])).to eq(:forbidden)
            expect(owned_row_counts(persona)).to eq(before)
          end
        when :member
          it "#{persona} の member にも value" do
            expect(outcome(call(entry, world.members[persona]), [ *parent_paths.fetch(type_name), field_name ])).to eq(:value)
          end
        end
      end
    end
  end
end
