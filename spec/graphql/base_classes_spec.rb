require "rails_helper"

# 基底の型・リゾルバ・mutation が宣言の無いものを拒否し、拒否を FORBIDDEN に揃える
# （docs/architecture/graphql-schema.md「基底クラス」「ID と node」「エラー」「ページングと N+1」）
RSpec.describe "GraphQL の基底クラス" do
  let(:actor) { Partnerships::Actor.new(user_id: "u1", tenant_id: "t1", name: "name", email: "a@example.com", role: "member") }

  before do
    stub_const("SpecPolicy", Class.new(ApplicationPolicy) do
      def show? = record.fetch(:visible)
      def read? = user.role == "admin"
      def update? = record.fetch(:visible) && user.role == "admin"
    end)
  end

  def object_type(name, &block)
    Class.new(Types::BaseObject) do
      graphql_name name
      field :name, String, null: false
      class_exec(&block) if block
    end
  end

  def resolver(type, &block)
    Class.new(Resolvers::BaseResolver) do
      graphql_name "ItemResolver"
      type type, null: true
      define_method(:resolve) { { name: "item", visible: true } }
      class_exec(&block) if block
    end
  end

  # 本番のスキーマを継承し、上書きした unauthorized_object・object_from_id や上限をそのまま使う
  def schema_with(query_fields, mutation_fields = nil)
    query = Class.new(Types::BaseObject) do
      graphql_name "Query"
      perspective :root
      authorization_exempt reason: "spec"
      class_exec(&query_fields)
    end
    mutation = mutation_fields && Class.new(Types::BaseObject) do
      graphql_name "Mutation"
      perspective :root
      authorization_exempt reason: "spec"
      class_exec(&mutation_fields)
    end
    Class.new(FactoryOpsSchema) do
      query(query)
      mutation(mutation) if mutation
    end
  end

  def run(schema, query_string, role: "member")
    schema.execute(query_string, context: { current_user: actor.with(role:) }).to_h
  end

  describe "型" do
    it "視点の宣言が無ければ例外" do
      type = object_type("Item") { authorization_exempt reason: "spec" }
      schema = schema_with(proc { field :item, type, null: true, resolver_method: :item; define_method(:item) { { name: "x" } } })

      expect { run(schema, "{ item { name } }") }.to raise_error(AuthorizationDeclarations::MissingDeclaration, /perspective/)
    end

    it "認可の宣言が無ければ例外" do
      type = object_type("Item") { perspective :supplier }
      schema = schema_with(proc { field :item, type, null: true, resolver_method: :item; define_method(:item) { { name: "x" } } })

      expect { run(schema, "{ item { name } }") }.to raise_error(AuthorizationDeclarations::MissingDeclaration, /authorization/)
    end

    it "本番では宣言が無ければ FORBIDDEN にしてエラー通知に送る" do
      allow(Rails.env).to receive(:local?).and_return(false)
      allow(Rails.error).to receive(:report)
      type = object_type("Item") { perspective :supplier }
      schema = schema_with(proc { field :item, type, null: true, resolver_method: :item; define_method(:item) { { name: "x" } } })

      result = run(schema, "{ item { name } }")

      expect(result["data"]).to eq("item" => nil)
      expect(result["errors"].map { |error| error.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
      expect(Rails.error).to have_received(:report).with(an_instance_of(AuthorizationDeclarations::MissingDeclaration))
    end

    it "policy の show? が偽なら null にし、FORBIDDEN を返してエラー通知に送る" do
      allow(Rails.error).to receive(:report)
      type = object_type("Item") do
        perspective :supplier
        authorize_with SpecPolicy
      end
      schema = schema_with(proc do
        field :items, [ type, { null: true } ], null: false, resolver_method: :items
        define_method(:items) { [ { name: "shown", visible: true }, { name: "hidden", visible: false } ] }
      end)

      result = run(schema, "{ items { name } }")

      expect(result.dig("data", "items")).to eq([ { "name" => "shown" }, nil ])
      expect(result["errors"].map { |error| error.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
      expect(Rails.error).to have_received(:report).with(an_instance_of(GraphQL::UnauthorizedError))
    end

    it "コネクションとエッジは中身の型の視点を持ち、宣言を持つ PageInfo を返す" do
      type = object_type("Item") do
        perspective :buyer
        authorization_exempt reason: "spec"
      end

      expect(type.connection_type.perspective).to eq(:buyer)
      expect(type.edge_type.perspective).to eq(:buyer)
      expect(type.connection_type.fields["pageInfo"].type.unwrap).to eq(Types::PageInfoType)
    end
  end

  describe "リゾルバ" do
    let(:type) do
      object_type("Item") do
        perspective :supplier
        authorization_exempt reason: "spec"
      end
    end

    it "宣言が無ければ例外" do
      item = resolver(type)
      schema = schema_with(proc { field :item, resolver: item })

      expect { run(schema, "{ item { name } }") }.to raise_error(AuthorizationDeclarations::MissingDeclaration)
    end

    it "規則が偽なら FORBIDDEN、真なら解決する" do
      item = resolver(type) do
        perspective :supplier
        authorize_with SpecPolicy, :read?
      end
      schema = schema_with(proc { field :item, resolver: item })

      denied = run(schema, "{ item { name } }")
      expect(denied["data"]).to eq("item" => nil)
      expect(denied["errors"].map { |error| error.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])

      expect(run(schema, "{ item { name } }", role: "admin")).to eq("data" => { "item" => { "name" => "item" } })
    end
  end

  describe "mutation" do
    let(:type) do
      object_type("Item") do
        perspective :supplier
        authorization_exempt reason: "spec"
      end
    end

    def mutation(type, name, &block)
      Class.new(Mutations::BaseMutation) do
        graphql_name name
        argument :id, GraphQL::Types::ID
        argument :quantity, Integer, required: false
        result_field :item, type
        class_exec(&block) if block
      end
    end

    def mutate(mutation_class, input, role: "admin")
      schema = schema_with(proc { field :item, String; define_method(:item) { "" } }, proc { field :save_item, mutation: mutation_class })
      run(schema, "mutation { saveItem(input: #{input}) { item { name } errors { code message path } } }", role:)
    end

    it "宣言が無ければ例外" do
      save = mutation(type, "SaveItem") { define_method(:perform) { |**| OperationResult.success({ name: "x" }) } }

      expect { mutate(save, '{ id: "1" }') }.to raise_error(AuthorizationDeclarations::MissingDeclaration)
    end

    describe "対象を引かない作成系" do
      let(:save) do
        mutation(type, "SaveItem") do
          perspective :supplier
          authorize_with SpecPolicy, :read?

          define_method(:perform) do |id:, quantity: nil|
            next OperationResult.failure(:invalid_input, path: [ :lines, 0, :unit_price ]) if quantity.to_i.negative?

            OperationResult.success({ name: "saved #{id}" })
          end
        end
      end

      it "操作者に対して規則を評価し、偽なら FORBIDDEN" do
        result = mutate(save, '{ id: "1" }', role: "member")

        expect(result["data"]).to eq("saveItem" => nil)
        expect(result["errors"].map { |error| error.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
      end

      it "成功なら値を返し、errors は空" do
        expect(mutate(save, '{ id: "1" }').dig("data", "saveItem")).to eq("item" => { "name" => "saved 1" }, "errors" => [])
      end

      it "失敗の結果を UserError に写し、値は空にする" do
        expect(mutate(save, '{ id: "1", quantity: -1 }').dig("data", "saveItem")).to eq(
          "item" => nil,
          "errors" => [ { "code" => "INVALID_INPUT", "message" => "Invalid input", "path" => %w[lines 0 unitPrice] } ]
        )
      end
    end

    describe "対象を引く操作" do
      let(:save) do
        mutation(type, "UpdateItem") do
          perspective :supplier
          authorize_with SpecPolicy, :update?

          define_method(:find_target) do |id:, **|
            { "visible" => { name: "visible", visible: true }, "other" => { name: "other", visible: false } }[id]
          end
          define_method(:perform) { |target, **| OperationResult.success(target) }
        end
      end

      it "対象が引けなければ NOT_FOUND を返す" do
        expect(mutate(save, '{ id: "missing" }').dig("data", "saveItem")).to eq(
          "item" => nil, "errors" => [ { "code" => "NOT_FOUND", "message" => "Not found", "path" => nil } ]
        )
      end

      it "引いた対象に対して規則を評価し、偽なら FORBIDDEN" do
        result = mutate(save, '{ id: "other" }')

        expect(result["data"]).to eq("saveItem" => nil)
        expect(result["errors"].map { |error| error.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
      end

      it "規則が真なら操作する" do
        expect(mutate(save, '{ id: "visible" }').dig("data", "saveItem", "item")).to eq("name" => "visible")
      end
    end

    it "戻り値の型は mutation の視点を持ち、認可の例外になる" do
      payload = mutation(type, "SaveItem") { perspective :supplier }.payload_type

      expect(payload.perspective).to eq(:supplier)
      expect(payload.authorization_exempt_reason).to be_present
    end
  end

  describe "ID と node" do
    it "Query に node と nodes が無い" do
      expect(FactoryOpsSchema.query.fields.keys).not_to include("node", "nodes")
    end

    it "object_from_id は例外" do
      expect { FactoryOpsSchema.object_from_id("1", {}) }.to raise_error(NotImplementedError)
    end

    it "引数の loads: は object_from_id を通るので例外" do
      type = object_type("Item") do
        perspective :supplier
        authorization_exempt reason: "spec"
      end
      schema = schema_with(proc do
        field :item, type, null: true do
          argument :item_id, GraphQL::Types::ID, loads: type, as: :item
        end
        define_method(:item) { |item:| item }
      end)

      expect { run(schema, '{ item(itemId: "1") { name } }') }.to raise_error(NotImplementedError)
    end
  end

  describe "クエリの上限と Dataloader" do
    it "深さ・複雑度・1 ページの件数に上限がある" do
      expect(FactoryOpsSchema).to have_attributes(
        max_depth: 10, max_complexity: 2_500, default_page_size: 20, default_max_page_size: 100
      )
    end

    it "Dataloader は Fiber を同じ接続で動かす。AsyncDataloader を使わず、isolation_level は :thread" do
      expect(FactoryOpsSchema.dataloader_class).to eq(GraphQL::Dataloader)
      expect(ActiveSupport::IsolatedExecutionState.isolation_level).to eq(:thread)
    end
  end
end
