require "prism"

# packwerk は公開 API の中のクラスを区別しないので、purchasing から sales への参照を
# Sales::PublishedCatalog だけに絞る規則（context-map.md「許可する依存の向き」）はここで守る
module PurchasingCatalogGuard
  ALLOWED = /\A(::)?Sales::PublishedCatalog(::|\z)/

  # 最も外側の定数参照だけを集める（Sales::Order::Line なら Sales::Order::Line の 1 つ）
  class SalesReferences < Prism::Visitor
    attr_reader :names

    def initialize
      @names = []
    end

    def visit_constant_path_node(node)
      name = node.full_name
      @names << name if name.match?(/\A(::)?Sales(::|\z)/)
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
      super
    end

    def visit_constant_read_node(node)
      @names << node.name.to_s if node.name == :Sales
    end
  end

  def self.forbidden_references(source)
    references = SalesReferences.new
    Prism.parse(source).value.accept(references)
    references.names.grep_v(ALLOWED)
  end
end

RSpec.describe "purchasing から sales への参照" do
  it "packs/purchasing は Sales::PublishedCatalog 以外の Sales の定数を参照しない" do
    root = File.expand_path("../../packs/purchasing", __dir__)
    violations = Dir.glob("**/*.rb", base: root).flat_map do |path|
      PurchasingCatalogGuard.forbidden_references(File.read(File.join(root, path))).map { |name| "#{path}: #{name}" }
    end

    expect(violations).to be_empty
  end

  it "Sales::PublishedCatalog 以外への参照を検出する" do
    source = <<~RUBY
      Sales::PublishedCatalog.items
      Sales::PublishedCatalog::Item
      Sales::Order.find(1)
      ::Sales::Allocation
      Sales
    RUBY

    expect(PurchasingCatalogGuard.forbidden_references(source)).to eq(%w[Sales::Order ::Sales::Allocation Sales])
  end
end
