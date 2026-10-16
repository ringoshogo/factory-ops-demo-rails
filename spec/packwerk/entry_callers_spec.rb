require "rails_helper"
require "prism"

# 呼ぶ側を限る入口の守り（docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」、
# docs/architecture/context-map.md「疎結合を守る規則」）。packwerk はパッケージの単位で参照を許すので、公開 API のうち
# 呼んでよい場所が決まったものを区別しない。本体のコードを Prism で読み、次の 3 つを確かめる。
# (i) 配送表の受け手は、自分のファイルの外で定数として参照されない。EventJob は配送表の文字列から名前を解決する
# (ii) 操作者のいない入口の公開 API は、設計文書の表の「呼んでよい場所」の外から呼ばれない
# (iii) テナントの設定を求める公開の特異メソッド（受け手の handle を除く）が、表のうちテナントが決まる前の入口を除いた行と等しい
# spec の配下は読まない。競合テストは受け手を直に呼ぶからである
module EntryCallers
  SOURCES = %w[app/**/*.rb packs/*/app/**/*.rb packs/*/lib/**/*.rb lib/**/*.{rb,rake} config/**/*.rb db/seeds.rb].freeze
  TABLE_HEADER = "| 公開 API | 呼んでよい場所 | テナント |"

  Call = Data.define(:path, :nesting, :receiver, :name)

  # 1 つのファイルの、定数の参照と、定数を受け手にした呼び出しと、特異メソッドの定義を集める
  class Collector < Prism::Visitor
    attr_reader :path, :defined, :references, :calls, :definitions

    def initialize(path)
      super()
      @path = path
      @nesting = []
      @defined = Set.new
      @references = []
      @calls = []
      @definitions = []
      @hidden = []
      @method = nil
      @singleton = false
      @private = false
    end

    def visit_module_node(node) = within(node.constant_path) { visit(node.body) }
    def visit_class_node(node)
      visit(node.superclass)
      within(node.constant_path) { visit(node.body) }
    end

    def visit_constant_read_node(node) = (@references << [ node.name.to_s, @nesting.dup ])

    def visit_constant_path_node(node)
      @references << [ node.full_name, @nesting.dup ]
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
      super
    end

    # class << self の中の def も特異メソッドに数え、その中の private の後のものは非公開にする
    def visit_singleton_class_node(node)
      return super unless node.expression.is_a?(Prism::SelfNode)

      singleton, privately = @singleton, @private
      @singleton, @private = true, false
      super
    ensure
      @singleton, @private = singleton, privately
    end

    def visit_def_node(node)
      return super unless node.receiver.is_a?(Prism::SelfNode) || (@singleton && node.receiver.nil?)

      @method = { name: node.name.to_s, requires_tenant: false, helpers: Set.new }
      super
      @hidden << [ @nesting.join("::"), node.name.to_s ] if @singleton && @private
      @definitions << @method.merge(constant: @nesting.join("::"))
      @method = nil
    end

    def visit_call_node(node)
      receiver = node.receiver
      if receiver.is_a?(Prism::ConstantReadNode) || receiver.is_a?(Prism::ConstantPathNode)
        name = receiver.is_a?(Prism::ConstantReadNode) ? receiver.name.to_s : receiver.full_name
        @calls << Call.new(path: @path, nesting: @nesting.dup, receiver: name, name: node.name.to_s)
        @method[:requires_tenant] = true if @method && name.delete_prefix("::") == "Tenancy" && node.name == :require_tenant!
      elsif @method && (receiver.nil? || receiver.is_a?(Prism::SelfNode))
        @method[:helpers] << node.name.to_s
      end
      if receiver.nil? && node.name == :private_class_method && node.arguments
        node.arguments.arguments.grep(Prism::SymbolNode).each { @hidden << [ @nesting.join("::"), _1.unescaped ] }
      end
      @private = true if @singleton && receiver.nil? && node.name == :private && node.arguments.nil?
      super
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
      super
    end

    def hidden?(constant, name) = @hidden.include?([ constant, name ])

    private

    def within(path)
      @nesting.push(path.full_name)
      @defined << @nesting.join("::")
      yield
    ensure
      @nesting.pop
    end
  end

  # sources は { パス => ソース } で、本体のコードを読むときは read(root) が作る
  def self.read(root) = SOURCES.flat_map { Dir.glob(_1, base: root) }.uniq.sort.to_h { [ _1, File.read(File.join(root, _1)) ] }

  def self.collect(sources)
    sources.map do |path, source|
      Collector.new(path).tap { Prism.parse(source).value.accept(_1) }
    end
  end

  # 書いた名前を、入れ子の定数の中から指したときの完全な名前の候補（内側から外側へ）
  def self.candidates(name, nesting)
    return [ name.delete_prefix("::") ] if name.start_with?("::")

    nesting.size.downto(0).map { [ *nesting.first(_1), name ].join("::") }
  end

  def self.refers?(name, nesting, constant) = candidates(name, nesting).include?(constant)

  # (i) 受け手の定数を、受け手を定義したファイルの外で参照した箇所
  def self.receiver_references(collectors, receivers)
    collectors.flat_map do |collector|
      collector.references.filter_map do |name, nesting|
        receiver = receivers.find { refers?(name, nesting, _1) }
        "#{collector.path}: #{receiver}" if receiver && !collector.defined.include?(receiver)
      end
    end
  end

  # (ii) 表の公開 API を、表の呼んでよい場所の外から呼んだ箇所。場所はファイルのパスか定数の名前で、定数はその中の入れ子も含む
  def self.misplaced_calls(collectors, table)
    collectors.flat_map(&:calls).filter_map do |call|
      api, row = table.find { |api, _| refers_api?(call, api) }
      next unless api
      next if row.fetch(:places).any? { |place| call.path == place || inside?(call.nesting.join("::"), place) }

      "#{call.path}: #{api}"
    end
  end

  # (iii) packs/*/app/public の、テナントの設定を求める公開の特異メソッド。同じ定数の非公開の特異メソッドを通して求めるものも、
  # 同じ定数の中の呼び出しをたどって数える
  def self.tenant_requiring(collectors, excluded)
    collectors.select { _1.path.match?(%r{\Apacks/[^/]+/app/public/}) }.flat_map do |collector|
      by_constant = collector.definitions.group_by { _1[:constant] }
      by_constant.flat_map do |constant, definitions|
        methods = definitions.to_h { [ _1[:name], _1 ] }
        requiring = Set.new
        loop do
          added = methods.values.reject { requiring.include?(_1[:name]) }.select { _1[:requires_tenant] || _1[:helpers].intersect?(requiring) }
          break if added.empty?

          requiring.merge(added.map { _1[:name] })
        end
        requiring.reject { collector.hidden?(constant, _1) }.map { "#{constant}.#{_1}" }
      end
    end.to_set - excluded
  end

  # 表を { "定数.メソッド" => { places: [場所], before_tenant: 真偽 } } にする。場所のセルは、` で囲んだファイルか定数を「、」で並べる
  def self.parse_table(markdown)
    rows = markdown.lines.drop_while { _1.chomp != TABLE_HEADER }.drop(2).take_while { _1.start_with?("|") }
    raise ArgumentError, "表が無い: #{TABLE_HEADER}" if rows.empty?

    rows.to_h do |row|
      api, places, tenant = row.split("|").map(&:strip).reject(&:empty?)
      [ api.delete("`"), { places: places.scan(/`([^`]+)`/).flatten, before_tenant: tenant == "決まる前" } ]
    end
  end

  def self.refers_api?(call, api)
    constant, name = api.split(".", 2)
    call.name == name && refers?(call.receiver, call.nesting, constant)
  end

  def self.inside?(constant, place) = constant == place || constant.start_with?("#{place}::")
end

RSpec.describe "呼ぶ側を限る入口" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:collectors) { EntryCallers.collect(EntryCallers.read(root)) }
  let(:receivers) { Contracts::Subscriptions::TABLE.values.flatten.map(&:receiver).uniq }
  let(:handles) { receivers.map { "#{_1}.handle" }.to_set }
  let(:table) { EntryCallers.parse_table(File.read(File.join(root, "docs/architecture/graphql-schema.md"))) }

  def collect(sources) = EntryCallers.collect(sources)

  describe "本体のコード" do
    it "配送表の受け手を、受け手のファイルの外で定数として参照しない" do
      # 対照：受け手の定数は、それぞれのファイルが定義している
      expect(receivers.map { |receiver| collectors.count { _1.defined.include?(receiver) } }).to all(eq(1))
      expect(EntryCallers.receiver_references(collectors, receivers)).to be_empty
    end

    it "操作者のいない入口の公開 API を、表の呼んでよい場所の外から呼ばない" do
      # 対照：表のどの公開 API も、本体のどこかから呼ばれている
      called = table.keys.select { |api| collectors.flat_map(&:calls).any? { EntryCallers.refers_api?(_1, api) } }
      expect(called).to match_array(table.keys)
      expect(EntryCallers.misplaced_calls(collectors, table)).to be_empty
    end

    it "テナントの設定を求める公開の特異メソッドが、表のうちテナントが決まる前の入口を除いた行と等しい" do
      requiring = EntryCallers.tenant_requiring(collectors, handles)

      expect(requiring).to eq(table.reject { _2[:before_tenant] }.keys.to_set)
      expect(table.select { _2[:before_tenant] }.keys).to contain_exactly(
        "Partnerships::Authentication.authenticate", "Partnerships::Onboarding.register", "Partnerships::Onboarding.tenant_id"
      )
      # 非公開の補助（own_users）を通してテナントの設定を求める 5 つも数える
      expect(requiring).to include("Partnerships::Authentication.actor", "Partnerships::Authentication.acting_user",
        "Partnerships::Authentication.revoke_sessions", "Partnerships::Recipients.admin_ids", "Partnerships::Recipients.emails")
    end
  end

  describe "違反を含むソース" do
    let(:receiver) { "Sales::PurchaseOrderTranslator" }
    let(:sources) do
      {
        "packs/sales/app/public/sales/purchase_order_translator.rb" => <<~RUBY,
          module Sales
            module PurchaseOrderTranslator
              def self.handle(event) = PurchaseOrderTranslator.name
            end
          end
        RUBY
        "packs/sales/app/public/sales/catalog.rb" => <<~RUBY
          module Sales
            module Catalog
              def self.save = Inventory::ItemLabels.put([])
            end
          end
        RUBY
      }
    end
    let(:rows) { { "Inventory::ItemLabels.put" => { places: [ "Sales::Catalog" ], before_tenant: false } } }

    it "(i) 受け手を、受け手のファイルの外で参照すると落ちる" do
      # 対照：受け手のファイルの中の参照は数えない
      expect(EntryCallers.receiver_references(collect(sources), [ receiver ])).to be_empty

      violating = sources.merge("app/graphql/x.rb" => "module Mutations\n  def self.x = ::Sales::PurchaseOrderTranslator\nend\n",
        "packs/sales/app/models/sales/y.rb" => "module Sales\n  class Y\n    def z = PurchaseOrderTranslator.handle(1)\n  end\nend\n")
      expect(EntryCallers.receiver_references(collect(violating), [ receiver ]))
        .to contain_exactly("app/graphql/x.rb: #{receiver}", "packs/sales/app/models/sales/y.rb: #{receiver}")
    end

    it "(ii) 表の公開 API を、呼んでよい場所の外から呼ぶと落ちる" do
      # 対照：呼んでよい定数の中の呼び出しは通す
      expect(EntryCallers.misplaced_calls(collect(sources), rows)).to be_empty

      violating = sources.merge("packs/purchasing/app/public/purchasing/x.rb" => <<~RUBY, "lib/tasks/x.rake" => "Inventory::ItemLabels.put([])\n")
        module Purchasing
          module X
            def self.y = Inventory::ItemLabels.put([])
          end
        end
      RUBY
      expect(EntryCallers.misplaced_calls(collect(violating), rows))
        .to contain_exactly("packs/purchasing/app/public/purchasing/x.rb: Inventory::ItemLabels.put", "lib/tasks/x.rake: Inventory::ItemLabels.put")
      # 呼んでよい場所にファイルを書いた行は、そのファイルからの呼び出しを通す
      expect(EntryCallers.misplaced_calls(collect(violating), rows.transform_values { _1.merge(places: [ *_1[:places], "lib/tasks/x.rake" ]) }))
        .to eq([ "packs/purchasing/app/public/purchasing/x.rb: Inventory::ItemLabels.put" ])
    end

    it "(iii) テナントの設定を直に求める公開 API と、非公開の補助を通して求める公開 API を、どちらも数える" do
      source = <<~RUBY
        module Partnerships
          module Recipients
            def self.direct
              Tenancy.require_tenant!
            end

            def self.through_helper = own_users.to_a
            def self.unrelated = 1

            def self.own_users
              Tenancy.require_tenant!
            end
            private_class_method :own_users
          end
        end
      RUBY
      requiring = EntryCallers.tenant_requiring(collect("packs/partnerships/app/public/partnerships/recipients.rb" => source), Set.new)

      expect(requiring).to eq(Set["Partnerships::Recipients.direct", "Partnerships::Recipients.through_helper"])
      # class << self の中の def も、直に呼ぶ形と非公開の補助を通す形の両方を数え、private の後の補助は公開に数えない
      singleton = <<~RUBY
        module Imports
          module Runs
            class << self
              def direct = Tenancy.require_tenant!
              def through_helper = own_rows
              def unrelated = 1

              private

              def own_rows = Tenancy.require_tenant!
            end
          end
        end
      RUBY
      expect(EntryCallers.tenant_requiring(collect("packs/imports/app/public/imports/runs.rb" => singleton), Set.new))
        .to eq(Set["Imports::Runs.direct", "Imports::Runs.through_helper"])
      # app/public の外のファイルと、除いた受け手の handle は数えない
      expect(EntryCallers.tenant_requiring(collect("packs/partnerships/app/models/partnerships/recipients.rb" => source), Set.new)).to be_empty
      expect(EntryCallers.tenant_requiring(collect("packs/partnerships/app/public/partnerships/recipients.rb" => source),
        Set["Partnerships::Recipients.direct"])).to eq(Set["Partnerships::Recipients.through_helper"])
    end
  end
end
