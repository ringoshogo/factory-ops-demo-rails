require "rails_helper"
require "prism"

# 外部への作用の呼び出し元は、通知の種類ごとに 1 か所で、登録された種類である（docs/adr/007 決定 4）。
# 再送や手動の再実行のために 2 か所目の呼び出しを足すと落ちる。再送は Notifications::Email.redeliver_failed を使う
RSpec.describe "通知の呼び出し元" do
  METHODS = { deliver_critical: :critical, deliver_best_effort: :best_effort }.freeze
  Call = Data.define(:path, :line, :method_name, :kind)

  # Notifications::Email.deliver_* の呼び出しを集める。種類はシンボルのリテラルでなければ nil にする
  class CallCollector < Prism::Visitor
    attr_reader :calls

    def initialize(path)
      super()
      @path = path
      @calls = []
    end

    def visit_call_node(node)
      if METHODS.key?(node.name) && node.receiver.is_a?(Prism::ConstantPathNode) &&
          node.receiver.full_name.delete_prefix("::") == "Notifications::Email"
        first = node.arguments&.arguments&.first
        kind = first.is_a?(Prism::SymbolNode) ? first.unescaped.to_sym : nil
        @calls << Call.new(path: @path, line: node.location.start_line, method_name: node.name, kind:)
      end
      super
    end
  end

  def self.collect(path, source)
    CallCollector.new(path).tap { Prism.parse(source).value.accept(_1) }.calls
  end

  def self.calls
    Dir[Rails.root.join("packs/*/app/**/*.rb")].sort.flat_map do |file|
      collect(Pathname(file).relative_path_from(Rails.root).to_s, File.read(file))
    end
  end

  let(:calls) { self.class.calls }

  it "どの通知の種類も、呼び出しが 1 か所だけある" do
    counts = Notifications::Catalog::KINDS.keys.index_with { |kind| calls.count { _1.kind == kind } }

    expect(counts).to eq(Notifications::Catalog::KINDS.keys.index_with { 1 })
  end

  it "呼び出しの種類は、シンボルのリテラルで書いた、登録された種類で、保証が呼び出しのメソッドと合う" do
    mismatched = calls.reject do |call|
      kind = Notifications::Catalog::KINDS[call.kind]
      kind && kind.guarantee == METHODS.fetch(call.method_name)
    end

    expect(mismatched).to eq([])
  end

  describe "集め方" do
    it "2 か所目の呼び出し・シンボルでない種類・別の受け手・先頭に :: を付けた受け手を区別する" do
      source = <<~RUBY
        module Shop
          def self.a = Notifications::Email.deliver_critical(:received_invoice, key: "k", params: {})
          def self.b = Notifications::Email.deliver_critical(:received_invoice, key: "k2", params: {})
          def self.c(kind) = Notifications::Email.deliver_best_effort(kind, params: {})
          def self.d = OtherMailer.deliver_critical(:received_invoice)
          def self.e = ::Notifications::Email.deliver_best_effort(:new_sales_order, params: {})
        end
      RUBY

      expect(self.class.collect("x.rb", source).map { [ _1.method_name, _1.kind ] })
        .to eq([ %i[deliver_critical received_invoice], %i[deliver_critical received_invoice], [ :deliver_best_effort, nil ],
          %i[deliver_best_effort new_sales_order] ])
    end
  end
end
