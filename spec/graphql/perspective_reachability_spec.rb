require "rails_helper"

# 発注側の視点から受注側の型へたどれない（docs/architecture/graphql-schema.md「相手側の型へたどれないことの保証」、adr/004）
RSpec.describe "視点ごとの型の到達可能性" do
  # 相手テナントのデータを返してよい発注側の型と、その読む経路。4 つ目を足すと落ちる
  cross_tenant_types = {
    "PublishedCatalogItem" => :catalog,
    "SupplierPartnership" => :partnerships,
    "SupplierShipment" => :shipments
  }

  # Query のフィールドと、その返す型（docs/architecture/graphql-schema.md「視点ごとに型を分ける」）
  let(:root_entries) { { "viewer" => "Viewer", "buyer" => "BuyerView", "supplier" => "SupplierView" } }

  let(:schema) { FactoryOpsSchema }
  # extra_types は schema.types に現れないので足す
  let(:object_types) { (schema.types.values + schema.extra_types).uniq.select { |type| type.kind.object? && !type.introspection? } }

  def field_types(type)
    type.fields.values.map { |field| field.type.unwrap }
  end

  # 入口からフィールドをたどって届く object の型
  def reachable_from(roots)
    seen = {}
    queue = roots.dup
    while (type = queue.shift)
      next if seen[type.graphql_name] || !type.kind.object?

      seen[type.graphql_name] = type
      queue.concat(field_types(type))
    end
    seen.values
  end

  def roots_of(perspective)
    view = schema.get_type(perspective == :buyer ? "BuyerView" : "SupplierView")
    mutations = schema.mutation&.fields&.values.to_a.select { |field| field.resolver.try(:perspective) == perspective }
    [ view, *mutations.map { |field| field.type.unwrap } ]
  end

  # ルートに視点の入口を通らないフィールドを足すと、上の到達可能性の検査を素通りする
  def root_violations(schema)
    entries = schema.query.fields.transform_values { |field| field.type.unwrap.graphql_name }
    extra_entries = entries.reject { |name, type| root_entries[name] == type }.map { |name, type| "Query.#{name}: #{type}" }
    missing_entries = (root_entries.keys - entries.keys).map { |name| "Query.#{name} が無い" }
    undeclared_mutations = schema.mutation&.fields&.values.to_a
      .reject { |field| %i[buyer supplier].include?(field.resolver.try(:perspective)) }
      .map { |field| "Mutation.#{field.name}" }

    extra_entries + missing_entries + undeclared_mutations
  end

  it "Query は viewer と視点の入口だけを持ち、Mutation の各フィールドは buyer か supplier を宣言した mutation である" do
    expect(root_violations(schema)).to be_empty
  end

  it "ルートの検査は、Query に足した受注側の型と、視点を宣言しない Mutation のフィールドを見つける" do
    query_type = Class.new(Types::QueryType) do
      graphql_name "Query"
      field :supplier_view, Types::SupplierViewType, null: false
    end
    mutation_type = Class.new(Types::BaseObject) do
      graphql_name "Mutation"
      perspective :root
      authorization_exempt reason: "テスト用"
      field :undeclared, String
    end
    bad_schema = Class.new(GraphQL::Schema) do
      query query_type
      mutation mutation_type
    end

    expect(root_violations(bad_schema)).to contain_exactly("Query.supplierView: SupplierView", "Mutation.undeclared")
  end

  %i[buyer supplier].each do |perspective|
    it "#{perspective} の入口と mutation の戻り値からたどれる型は #{perspective} か shared だけ" do
      violations = reachable_from(roots_of(perspective))
        .reject { |type| [ perspective, :shared ].include?(type.try(:perspective)) }
        .map { |type| "#{type.graphql_name} (#{type.try(:perspective).inspect})" }

      expect(violations).to be_empty
    end
  end

  it "shared の型のフィールドは、スカラー・enum・shared の型だけを返す" do
    violations = object_types.select { |type| type.try(:perspective) == :shared }.flat_map do |type|
      type.fields.values
        .reject { |field| field.type.unwrap.kind.scalar? || field.type.unwrap.kind.enum? || field.type.unwrap.try(:perspective) == :shared }
        .map { |field| "#{type.graphql_name}.#{field.name}" }
    end

    expect(violations).to be_empty
  end

  it "相手テナントのデータを返す型は、決めた発注側の型だけで、対応する読む経路を宣言している" do
    declared = object_types.select { |type| type.try(:cross_tenant_read) }

    expect(declared.to_h { |type| [ type.graphql_name, type.cross_tenant_read ] }).to eq(cross_tenant_types)
    expect(declared.map(&:perspective)).to all(eq(:buyer))
  end

  # 相手の内部の ID を出さず、品目コード・受注側テナント・連結先の発注で識別する（docs/architecture/graphql-schema.md「発注側の視点」）
  it "相手テナントのデータを返す型と、その明細の型は、ID のフィールドを持たない" do
    types = cross_tenant_types.keys + %w[SupplierShipmentLine]
    with_id = types.flat_map do |name|
      schema.get_type(name).fields.values.select { |field| field.type.unwrap == GraphQL::Types::ID }.map { "#{name}.#{_1.name}" }
    end

    expect(with_id).to be_empty
  end
end
