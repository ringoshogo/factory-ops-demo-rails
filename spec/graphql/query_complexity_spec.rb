require "rails_helper"

# 画面の問い合わせごとの複雑度が上限に収まり、コネクションを入れ子にした問い合わせが上限を超える
# （docs/architecture/graphql-schema.md「ページングと N+1」）。問い合わせは画面の問い合わせの一覧のファイルをすべて読むので、
# 一覧に足したファイルは表に書かなくても確かめる
RSpec.describe "画面の問い合わせの複雑度" do
  screens = Rails.root.join("spec/fixtures/graphql/screens").glob("*.graphql").sort

  # 1 ページの件数を上限まで求めたときの複雑度。first を省くと既定の件数で数えるので、問い合わせが取りうる最大で計る。
  # 必須の ID の変数には値を入れる。妥当でない問い合わせは、引数を解決できないフィールドを数え損ねる
  def complexity(text, schema = FactoryOpsSchema)
    variables = GraphQL.parse(text).definitions.sole.variables.to_h do |variable|
      next [ variable.name, schema.default_max_page_size ] if variable.name == "first"
      next [ variable.name, nil ] unless variable.type.is_a?(GraphQL::Language::Nodes::NonNullType)
      raise ArgumentError, "必須の変数 #{variable.name} の値の決め方が無い" unless variable.type.of_type.name == "ID"

      [ variable.name, SecureRandom.uuid ]
    end
    query = GraphQL::Query.new(schema, text, variables: variables.compact)
    expect(query.static_errors).to be_empty
    GraphQL::Analysis.analyze_query(query, [ GraphQL::Analysis::QueryComplexity ]).sole
  end

  it "画面の問い合わせの一覧にファイルがある" do
    expect(screens).not_to be_empty
  end

  it "必須の ID の変数に値を入れて計り、妥当でない問い合わせと、値の決め方の無い必須の変数では落ちる" do
    expect { complexity("query($id: ID!, $first: Int) { buyer { supplier(supplierTenantId: $id) { catalog(first: $first) { nodes { code } } } } }") }
      .not_to raise_error
    expect { complexity("query { supplier { unknownField } }") }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    expect { complexity("query($code: String!) { buyer { suppliers { supplier { name } } } }") }.to raise_error(ArgumentError)
  end

  screens.each do |path|
    it "#{path.basename} の複雑度が上限に収まる" do
      expect(complexity(path.read)).to be <= FactoryOpsSchema.max_complexity
    end
  end

  # いまのスキーマには、コネクションの要素の下にコネクションを持つ型が無いので、同じ上限を持つスキーマを作って確かめる。
  # リストの要素の下のコネクションは掛け算にならないので、その形は複雑度では止まらず、クエリ数の予算の spec が画面の問い合わせから外す
  it "コネクションの要素の下にコネクションを入れ子にした問い合わせは、上限を超えて拒否される" do
    item = Class.new(GraphQL::Schema::Object) { graphql_name("NestedItem") && field(:code, String) && field(:name, String) }
    order = Class.new(GraphQL::Schema::Object) { graphql_name("NestedOrder") && field(:items, item.connection_type) }
    query = Class.new(GraphQL::Schema::Object) { graphql_name("NestedQuery") && field(:orders, order.connection_type) }
    limits = FactoryOpsSchema
    schema = Class.new(GraphQL::Schema) do
      query(query)
      max_complexity limits.max_complexity
      default_max_page_size limits.default_max_page_size
    end
    text = "query($first: Int) { orders(first: $first) { nodes { items(first: $first) { nodes { code name } } } } }"

    expect(complexity(text, schema)).to be > FactoryOpsSchema.max_complexity
    expect(schema.execute(text, variables: { "first" => 100 })["errors"].map { _1["message"] })
      .to include(a_string_matching(/exceeds max complexity of #{FactoryOpsSchema.max_complexity}/))
    # 対照：入れ子にしなければ、同じ件数の一覧は上限に収まる
    expect(complexity("query($first: Int) { orders(first: $first) { nodes { __typename } } }", schema))
      .to be <= FactoryOpsSchema.max_complexity
  end
end
