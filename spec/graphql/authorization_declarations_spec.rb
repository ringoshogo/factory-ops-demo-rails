require "rails_helper"

# 宣言の無い型・リゾルバ・mutation がスキーマに無く、認可の例外が決めた一覧と一致する
# （docs/architecture/graphql-schema.md「明示的な例外と列挙テスト」）
RSpec.describe "GraphQL の認可の宣言" do
  # 認可の例外にしてよい型。mutation の戻り値・コネクション・エッジの型は、基底クラスが例外にする。
  # Mutation は最初の mutation と一緒に足す
  exempt_types = %w[Query Viewer BuyerView SupplierView Tenant UserError PageInfo]

  let(:schema) { FactoryOpsSchema }
  # extra_types は schema.types に現れないので足す
  let(:types) { (schema.types.values + schema.extra_types).uniq.reject(&:introspection?) }
  let(:object_types) { types.select { |type| type.kind.object? } }
  let(:generated_bases) { [ Types::BasePayload, Types::BaseConnection, Types::BaseEdge ] }
  let(:fields) { object_types.flat_map { |type| type.fields.values } }

  def describe_violations(members)
    members.map { |member| member.try(:graphql_name) || member.to_s }
  end

  it "型は object・スカラー・enum・input だけ（interface と union は宣言の検査を足してから使う）" do
    kinds = types.map { |type| type.kind.name }.uniq

    expect(kinds - %w[OBJECT SCALAR ENUM INPUT_OBJECT]).to be_empty
  end

  it "object の型はすべて Types::BaseObject から作られ、視点と認可を宣言している" do
    violations = object_types.reject do |type|
      type < Types::BaseObject && type.perspective && type.authorization_declared?
    end

    expect(describe_violations(violations)).to be_empty
  end

  it "認可の例外の型が一覧と一致する" do
    exempt = object_types.select(&:authorization_exempt_reason).reject { |type| generated_bases.any? { |base| type < base } }

    expect(exempt.map(&:graphql_name)).to match_array(exempt_types)
  end

  it "リゾルバと mutation はすべて基底クラスから作られ、buyer か supplier と規則を宣言している" do
    resolvers = fields.filter_map(&:resolver).uniq
    violations = resolvers.reject do |resolver|
      (resolver < Resolvers::BaseResolver || resolver < Mutations::BaseMutation) &&
        %i[buyer supplier].include?(resolver.perspective) &&
        resolver.authorization_policy && resolver.authorization_rule
    end

    expect(describe_violations(violations)).to be_empty
  end

  it "視点の入口のフィールドは、すべてその視点を宣言したリゾルバで書く" do
    violations = { "BuyerView" => :buyer, "SupplierView" => :supplier }.flat_map do |name, perspective|
      schema.get_type(name).fields.values.reject do |field|
        field.resolver&.<(Resolvers::BaseResolver) && field.resolver.perspective == perspective
      end
    end

    expect(violations.map(&:path)).to be_empty
  end

  it "Mutation のフィールドは、すべて基底 mutation から作る" do
    violations = schema.mutation&.fields&.values.to_a.reject { |field| field.resolver&.<(Mutations::BaseMutation) }

    expect(violations.map(&:path)).to be_empty
  end
end
