require "rails_helper"

# 宣言の無い型・リゾルバ・mutation がスキーマに無く、認可の例外が決めた一覧と一致する
# （docs/architecture/graphql-schema.md「明示的な例外と列挙テスト」）
RSpec.describe "GraphQL の認可の宣言" do
  # 認可の例外にしてよい型。mutation の戻り値・コネクション・エッジの型は、基底クラスが例外にする。
  exempt_types = %w[Query Mutation Viewer BuyerView SupplierView Tenant UserError PageInfo]

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

  # Viewer の下のリゾルバは、視点を問わない自社のデータを返すので shared を宣言する
  it "リゾルバと mutation はすべて基底クラスから作られ、視点（Viewer の下は shared、他は buyer か supplier）と規則を宣言している" do
    violations = fields.select(&:resolver).reject do |field|
      resolver = field.resolver
      perspectives = field.owner.graphql_name == "Viewer" ? %i[shared] : %i[buyer supplier]
      (resolver < Resolvers::BaseResolver || resolver < Mutations::BaseMutation) &&
        perspectives.include?(resolver.perspective) &&
        resolver.authorization_policy && resolver.authorization_rule
    end

    expect(violations.map(&:path)).to be_empty
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

  # 監査の宣言（docs/architecture/graphql-schema.md「監査ログ」）。表は後で作る mutation も載せるので、
  # スキーマにある mutation だけを表と比べる。スキーマにあって表に無い mutation は落とす
  describe "監査の宣言" do
    let(:audit_section) do
      Rails.root.join("docs/architecture/graphql-schema.md").read[/^### 監査ログ\n.*?(?=^##)/m] or raise "「監査ログ」の節が無い"
    end
    # 表の行を、先頭の列の値 => 残りの列の配列にする。header は表の見出しの行の先頭の列
    def table_rows(section, header)
      table = section[/^\| #{header} \|.*?(?=\n\n|\z)/m] or raise "見出しが「#{header}」の表が無い"
      table.lines.drop(2).to_h do |line|
        cells = line.strip.delete_prefix("|").delete_suffix("|").split("|").map { _1.strip.delete("`") }
        [ cells.first, cells.drop(1) ]
      end
    end
    let(:declared_kinds) do
      table_rows(audit_section, "宣言").flat_map { |kind, (names)| names.split("・").map { [ _1, kind ] } }.to_h
    end
    let(:declared_actions) { table_rows(audit_section, "mutation").transform_values(&:first) }
    let(:mutations) { schema.mutation.fields.values.to_h { [ _1.name, _1.resolver ] } }

    it "スキーマにある mutation は、すべて監査の宣言を持ち、表に行がある" do
      expect(mutations.reject { |_name, mutation| mutation.audit_declared? }.keys).to be_empty
      expect(mutations.keys - declared_kinds.keys).to be_empty
    end

    it "宣言の種類（audit か audit_exempt）が、表の行と一致する" do
      kinds = mutations.transform_values { _1.audit_action ? "audit" : "audit_exempt" }

      expect(kinds).to eq(declared_kinds.slice(*mutations.keys))
    end

    it "audit の mutation の action が、表の行と一致する" do
      actions = mutations.filter_map { |name, mutation| [ name, mutation.audit_action ] if mutation.audit_action }.to_h

      expect(actions).to eq(declared_actions.slice(*mutations.keys))
    end

    it "audit_exempt の mutation は、理由を書いている" do
      expect(mutations.values.reject(&:audit_action).map(&:audit_exempt_reason)).to all(be_present)
    end

    it "監査の宣言の無い mutation は、開発とテストで例外になる" do
      mutation = Class.new(Mutations::BaseMutation) do
        graphql_name "Undeclared"
        perspective :supplier
        authorize_with Sales::ItemPolicy, :save?
      end

      expect { mutation.check_declarations! }
        .to raise_error(AuthorizationDeclarations::MissingDeclaration, "Undeclared lacks audit declaration")
    end
  end
end
