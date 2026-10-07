require "rails_helper"

# 発注側の視点から受注側の型へたどれない（docs/architecture/graphql-schema.md「相手側の型へたどれないことの保証」、adr/004）
RSpec.describe "視点ごとの型の到達可能性" do
  # 相手テナントのデータを返してよい発注側の型と、その読む経路。4 つ目を足すと落ちる
  cross_tenant_types = {
    "PublishedCatalogItem" => :catalog,
    "SupplierPartnership" => :partnerships,
    "SupplierShipment" => :shipments
  }

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

    expect(cross_tenant_types).to include(declared.to_h { |type| [ type.graphql_name, type.cross_tenant_read ] })
    expect(declared.map(&:perspective)).to all(eq(:buyer))
  end
end
