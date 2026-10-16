require "rails_helper"
require "prism"

# 公開の特異メソッドを、ソースから「定数.メソッド」の名前で集める。def self. と class << self の中の def を数え、
# private_class_method で隠したものと class << self の中の private の後のものを除く
class PublicSingletonMethods < Prism::Visitor
  def initialize
    super
    @nesting = []
    @singleton = false
    @private = false
    @names = Set.new
    @hidden = Set.new
  end

  def names = @names - @hidden

  def visit_module_node(node) = within(node.constant_path.full_name) { super }
  def visit_class_node(node) = within(node.constant_path.full_name) { super }
  # X = Data.define(...) do ... end の中の def self. は X の特異メソッドである
  def visit_constant_write_node(node) = within(node.name.to_s) { super }

  def visit_singleton_class_node(node)
    return super unless node.expression.is_a?(Prism::SelfNode)

    singleton, privately = @singleton, @private
    @singleton, @private = true, false
    super
  ensure
    @singleton, @private = singleton, privately
  end

  def visit_def_node(node)
    if node.receiver.is_a?(Prism::SelfNode) || (@singleton && node.receiver.nil? && !@private)
      @names << "#{@nesting.join("::")}.#{node.name}"
    end
  end

  def visit_call_node(node)
    if node.receiver.nil? && node.name == :private_class_method
      node.arguments&.arguments&.each do |argument|
        name = argument.is_a?(Prism::DefNode) ? argument.name : argument.unescaped
        @hidden << "#{@nesting.join("::")}.#{name}"
      end
    end
    @private = true if @singleton && node.receiver.nil? && node.name == :private && node.arguments.nil?
    super
  end

  private

  def within(name)
    @nesting.push(name)
    yield
  ensure
    @nesting.pop
  end
end


# 公開 API の戻り値のガード（spec/support/public_api_returns.rb）が、確かめる対象を取りこぼさず、relation とモデルをどの入れ物に
# 入れても捕まえ、rspec-mocks の引数の確かめを壊さないこと（docs/guides/packs-and-packwerk.md「公開 API を出す」）
RSpec.describe PublicApiReturns do
  # 確かめない種類（Data の値・イベントの型・policy・ジョブ・例外のクラス）
  def unchecked?(name)
    constant = Object.const_get(name)
    constant.is_a?(Class) &&
      [ Data, Contracts::Event, ApplicationPolicy, ActiveJob::Base, Exception ].any? { constant <= _1 }
  end

  def expect_violation(&) = expect(&).to raise_error(PublicApiReturns::Violation, /PublicApiProbe\.returning/)

  let(:probe) do
    Module.new do
      def self.returning(value) = value
    end
  end

  let(:tenant) { FactoryBot.create(:tenant) }

  around { |example| TenantExample.run(example, tenant.id) }

  it "packs/*/app/public の公開の特異メソッドのうち、確かめない種類の定数のものを除いたすべてを確かめる" do
    expected = Rails.root.glob("packs/*/app/public/**/*.rb").flat_map do |path|
      visitor = PublicSingletonMethods.new
      Prism.parse_file(path.to_s).value.accept(visitor)
      visitor.names.to_a
    end.reject { unchecked?(_1.split(".").first) }

    expect(expected).not_to be_empty
    expect(PublicApiReturns.watched - [ "Page#values" ]).to match_array(expected)
  end

  describe "試しのモジュールを確かめる対象にしたとき" do
    before { PublicApiReturns.watch("PublicApiProbe.returning", probe.method(:returning)) }
    after { PublicApiReturns.unwatch("PublicApiProbe.returning") }

    it "relation かモデルを、そのまま返しても、どの入れ物に入れて返しても例外にする" do
      value = Data.define(:item)

      [ AuditLog.none, AuditLog.new ].each do |record|
        expect_violation { probe.returning(record) }
        expect_violation { probe.returning(OperationResult.success(record)) }
        expect_violation { probe.returning({ item: record }) }
        expect_violation { probe.returning({ record => 1 }) }
        expect_violation { probe.returning(Set[record]) }
        expect_violation { probe.returning(value.new(item: record)) }
        expect_violation { probe.returning([ 1, record ]) }
      end
    end

    it "副問い合わせ・Data の値・ID の配列は通す" do
      subquery = SqlSubquery.of(AuditLog.none.select(:id), id: "id")

      expect(probe.returning(subquery)).to eq(subquery)
      expect(probe.returning(OperationResult.success(Data.define(:id).new(id: 1))).value.id).to eq(1)
      expect(probe.returning([ SecureRandom.uuid ]).size).to eq(1)
    end

    # rspec-mocks は部分の二重の引数を、元のメソッドの引数の形で確かめる（spec/spec_helper.rb の verify_partial_doubles）。
    # 確かめを付けたメソッドでもこの確かめが効き、スタブを外した後も戻り値の確かめが残る
    it "スタブの引数の誤りを例外にし、スタブを外した後もまた確かめる" do
      RSpec::Mocks.with_temporary_scope do
        expect { allow(Inventory::Stocks).to receive(:for_items).with(1) }
          .to raise_error(RSpec::Mocks::MockExpectationError, /Wrong number of arguments/)
        expect { allow(probe).to receive(:returning).with(1, 2) }
          .to raise_error(RSpec::Mocks::MockExpectationError, /Wrong number of arguments/)
      end

      RSpec::Mocks.with_temporary_scope do
        allow(probe).to receive(:returning).and_return(AuditLog.none)
        expect(probe.returning(1)).to eq(AuditLog.none)
      end
      expect_violation { probe.returning(AuditLog.none) }
    end
  end

  it "Page#values のブロックが relation の行をそのまま返すと例外にし、値に写せば通す" do
    FactoryBot.create(:audit_log)

    expect { Page.of(AuditLog.all, first: 10, after: nil) { |records| records }.values }
      .to raise_error(PublicApiReturns::Violation, /Page#values/)
    expect(Page.of(AuditLog.all, first: 10, after: nil) { |records| records.map(&:id) }.values.size).to eq(1)
  end
end
