require "rails_helper"
require_relative "../support/matrix_world"
require_relative "graphql_expectations"

# 入口のフィールドと mutation ごとに、ペルソナとしてログインして実行し、結果の種類を確かめる
# （docs/architecture/context-map.md「テナントと所有」、docs/architecture/graphql-schema.md「エラー」）。
# 読み取りは RLS の SELECT を開いて送り直し、応答が変わらないことで scope を確かめる（docs/guides/testing.md「行列テストとの分担」）。
# どの行も member でも呼ぶ。admin に限る mutation は、値を返すペルソナの member に FORBIDDEN になって何も書かないことを、
# admin に限る読み取りは、どのペルソナの member にも行に書いた結果（FORBIDDEN か null）になることを、
# member に許す行は、どのペルソナの member にも admin と同じ結果になり、mutation が値を返さないときは何も書かないことを確かめる
# （docs/architecture/graphql-schema.md「役割による制限」）
RSpec.describe "入口の行列", type: :request do
  MatrixWorld.share_per_file(self, cross_read: true)

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

  # 視点の入口と Mutation のフィールド、Viewer の下のリゾルバと型のメソッドで書いたフィールド、
  # 入口の下で相手側の型を返すフィールド（読む経路）。視点の入口そのもの（Query.buyer・Query.supplier）は、データを持たないので除く。
  # Viewer の型のメソッドは、役割で値を変えるフィールド（partnerCode）を書く場所なので、役割の検査の行に入れる
  def schema_entries
    root_fields = ROOTS.filter_map { |name| FactoryOpsSchema.get_type(name) }.flat_map do |type|
      type.fields.values.reject { |field| field.type.unwrap.graphql_name.in?(%w[BuyerView SupplierView]) }
    end
    viewer = FactoryOpsSchema.get_type("Viewer")
    viewer_fields = viewer.fields.values.select { |field| field.resolver || viewer.method_defined?(field.method_sym, false) }
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

  # 変種の行（"型.フィールド#変種"）は、同じフィールドの行として数える
  def self.field_key(key) = key.split("#").first

  it "入口のフィールドと mutation すべてに期待値があり、無いフィールドの期待値は無い" do
    expect(MatrixExpectations::GRAPHQL.keys.map { self.class.field_key(_1) }.uniq).to match_array(schema_entries)
  end

  # ペルソナのテナントが所有する行の、テナントの表ごとの行数と中身の要約。監査の行も含む。
  # 行数だけを比べると、既存の行を書き換えるだけの mutation が書いても変わらない
  def owned_rows(persona)
    tenant_id = world.tenants.fetch(persona)
    world.as(persona) do
      connection = ActiveRecord::Base.lease_connection
      MatrixWorld.tenant_tables.index_with do |table|
        connection.select_rows(<<~SQL, "Matrix", [ tenant_id ]).first
          SELECT count(*), md5(coalesce(string_agg(t::text, ',' ORDER BY t.id), ''))
          FROM #{connection.quote_table_name(table)} t WHERE owner_tenant_id = $1
        SQL
      end
    end
  end

  # admin に限る読み取りは、member に返す結果（FORBIDDEN か null）を member: に書く。ほかの行の member の結果は、
  # admin に限る mutation なら FORBIDDEN、member に許す行なら admin と同じなので書かない
  it "行はすべて許す役割を持ち、admin に限る読み取りの行だけが member の結果を持つ" do
    MatrixExpectations::GRAPHQL.each do |key, entry|
      expect(ROLES).to include(entry[:role]), "#{key} に role: :admin か role: :member を書く"
      if entry[:role] == :admin && !key.start_with?("Mutation.")
        expect(MatrixExpectations::OUTCOMES).to include(entry[:member]), "#{key} に member: を書く"
      else
        expect(entry).not_to have_key(:member), key
      end
    end
  end

  it "期待値はすべてのペルソナについて、決めた結果の種類で書かれている" do
    MatrixExpectations::GRAPHQL.each do |key, entry|
      expect(entry[:expect].keys).to match_array(MatrixWorld::PERSONAS), key
      expect(entry[:expect].values - MatrixExpectations::OUTCOMES).to be_empty, key
    end
  end

  # 一覧の並びを無視して比べるための形。並びだけが違うときに、scope の抜けと区別して失敗させる
  def sorted_deep(value)
    case value
    when Array then value.map { sorted_deep(_1) }.sort_by(&:to_json)
    when Hash then value.transform_values { sorted_deep(_1) }
    else value
    end
  end

  MatrixExpectations::GRAPHQL.each do |key, entry|
    type_name, field_name = field_key(key).split(".")
    read = type_name != "Mutation"

    describe key do
      MatrixWorld::PERSONAS.each do |persona|
        # 読み取りは、同じ要求を RLS の SELECT を開いて送り直し、本文が変わらないことも確かめる（docs/guides/testing.md
        # 「行列テストとの分担」）。RLS が他社の行を隠すので、scope を外した公開 API は 1 回目の応答では見分けられない。
        # 結果の種類だけを比べると、集計を返す入口は scope を外しても種類が変わらないので、本文を比べる
        it "#{persona} には #{entry[:expect][persona]}#{'で、RLS の SELECT を開いても同じ応答' if read}" do
          variables = entry[:variables]&.call(world) || {}
          login_as(world.users[persona])
          post "/graphql", params: { query: entry[:query], variables: }, as: :json

          expect(outcome(response.parsed_body, [ *parent_paths.fetch(type_name), field_name ])).to eq(entry[:expect][persona])
          next unless read

          body = response.parsed_body
          MatrixCrossRead.on!
          post "/graphql", params: { query: entry[:query], variables: }, as: :json
          crossed = response.parsed_body

          expect(sorted_deep(crossed)).to eq(sorted_deep(body)), "RLS の SELECT を開くと応答が変わった。scope の抜けを疑う"
          expect(crossed).to eq(body), "一覧の並びだけが変わった。並びの決まらない一覧とは比べられない"
        end
      end

      entry[:expect].each do |persona, result|
        case entry[:role]
        when :admin
          if read
            it "#{persona} の member には #{entry[:member]}" do
              login_as(world.members[persona])
              post "/graphql", params: { query: entry[:query], variables: entry[:variables]&.call(world) || {} }, as: :json

              expect(outcome(response.parsed_body, [ *parent_paths.fetch(type_name), field_name ])).to eq(entry[:member])
            end
            next
          end
          next unless result == :value

          it "#{persona} の member には forbidden で、そのテナントの表に何も書かない" do
            variables = entry[:variables]&.call(world) || {}
            before = owned_rows(persona)
            login_as(world.members[persona])
            post "/graphql", params: { query: entry[:query], variables: }, as: :json

            expect(outcome(response.parsed_body, [ *parent_paths.fetch(type_name), field_name ])).to eq(:forbidden)
            expect(owned_rows(persona)).to eq(before)
          end
        when :member
          # 値を返さない結果では、member の要求も何も書かない。saveItem で既存の品目の単価を変えられないことは、ここで確かめる
          it "#{persona} の member にも #{result}#{'で、そのテナントの表に何も書かない' unless result == :value || read}" do
            variables = entry[:variables]&.call(world) || {}
            before = owned_rows(persona) unless read
            login_as(world.members[persona])
            post "/graphql", params: { query: entry[:query], variables: }, as: :json

            expect(outcome(response.parsed_body, [ *parent_paths.fetch(type_name), field_name ])).to eq(result)
            expect(owned_rows(persona)).to eq(before) unless result == :value || read
          end
        end
      end
    end
  end

  # 入れ子のフィールドが親の値から取った ID で呼ぶ公開 API を、app/graphql の書き方から集める。
  # dataloader の一括取得（Sources::PublicApiSource に渡すモジュールとメソッド。メソッドを変数で渡す型は、
  # 同じファイルの load_from(:メソッド) で補う）と、親の ID をそのまま渡す resolver の呼び出しである
  def nested_apis_in_graphql
    Rails.root.glob("app/graphql/**/*.rb").flat_map do |path|
      source = path.read
      found = source.scan(/PublicApiSource, ([A-Z]\w*(?:::[A-Z]\w*)+), :(\w+)/) +
        source.scan(/load_from\(([A-Z]\w*(?:::[A-Z]\w*)+), :(\w+)/) +
        source.scan(/([A-Z]\w*(?:::[A-Z]\w*)+)\.(\w+)\(current_user, object\.id/)
      variable = source[/PublicApiSource, ([A-Z]\w*(?:::[A-Z]\w*)+), method\b/, 1]
      found += source.scan(/load_from\(:(\w+)\)/).map { [ variable, _1.first ] } if variable
      found.map { _1.join(".") }
    end.uniq
  end

  def actor_for(persona)
    user = world.users.fetch(persona)
    Partnerships::Actor.new(user_id: user.id, tenant_id: user.owner_tenant_id, name: user.name, email: user.email, role: user.role,
      partner_code: "")
  end

  describe "入れ子のフィールドが親の ID で呼ぶ公開 API" do
    it "app/graphql が親の ID で呼ぶ公開 API すべてに行があり、無い公開 API の行は無い" do
      keys = MatrixExpectations::NESTED_APIS.keys + MatrixExpectations::NESTED_APIS_CROSS_TENANT.keys

      expect(keys).to match_array(nested_apis_in_graphql)
    end

    # 入口の行列は親の ID でしか子を引かないので、子の公開 API が scope を外しても 2 回目の応答は変わらない。
    # 全ペルソナの ID を直に渡し、RLS の SELECT を開いても、呼んだペルソナの ID にだけ値を返すことを確かめる。
    # 呼んだペルソナの ID に値が返ることが対照になる
    MatrixExpectations::NESTED_APIS.each do |key, entry|
      it "#{key} は、RLS の SELECT を開いても、他社の ID には値を返さない" do
        persona = entry.fetch(:persona, :supplier)
        ids = MatrixWorld::PERSONAS.index_with do |owner|
          world.as(owner) do
            entry[:setup]&.call(world, owner)
            entry[:ids] ? entry[:ids].call(world, owner) : world.row(entry[:table], owner).public_send(entry.fetch(:column, "id"))
          end
        end.compact
        api_name, method = key.split(".")
        api = api_name.constantize
        call = entry[:call] || ->(actor, values) { api.public_send(method, actor, values) }

        MatrixCrossRead.on!
        values = world.as(persona) { call.call(actor_for(persona), ids.values) }

        expect(ids.select { |_owner, id| values[id].present? }.keys).to eq([ persona ])
      end
    end
  end
end
