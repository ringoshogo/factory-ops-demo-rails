require "rails_helper"
require "prism"
require_relative "../support/matrix_world"

# example をテナントで包む around は、TenantExample.run を通す（spec/support/tenant_example.rb、docs/guides/testing.md「層への配分」）。
# Tenancy.with_tenant で直に包むと、example が SQL のエラーで落ちたときに around が送出し、rspec-rails の example ごとの
# トランザクションの巻き戻しが飛ぶ。残ったトランザクションは後ろの example に入れ子になり、後ろのグループを止めるか落とす
RSpec.describe "example をテナントで包む around" do
  # Tenancy.with_tenant で直に包む around。下の (i) の対照はこの文字列を内側の group に module_eval して流すので、
  # 実行できる形にする。spec のファイルに around のブロックとして書くと、ガードがこのファイルを落とす
  DIRECT_AROUND = "around { |example| Tenancy.with_tenant(SecureRandom.uuid) { example.run } }".freeze

  # around のブロックの中で、example をトランザクションで包む呼び出しを探す。呼び出しの名前を字面で探すので、
  # 補助のメソッドで包んで around から呼ぶ形は捕まえない
  class AroundCollector < Prism::Visitor
    AROUNDS = %i[around prepend_around append_around].freeze
    WRAPS = %i[with_tenant transaction].freeze

    attr_reader :wrapping, :tenant_examples

    def initialize
      super
      @wrapping = []
      @tenant_examples = []
    end

    def visit_call_node(node)
      if AROUNDS.include?(node.name) && node.block.is_a?(Prism::BlockNode)
        calls = calls_in(node.block)
        @wrapping << node.location.start_line if calls.any? { WRAPS.include?(_1.name) }
        @tenant_examples << node.location.start_line if calls.any? { tenant_example_run?(_1) }
      end
      super
    end

    private

    def calls_in(node)
      node.compact_child_nodes.flat_map { (_1.is_a?(Prism::CallNode) ? [ _1 ] : []) + calls_in(_1) }
    end

    def tenant_example_run?(call)
      call.name == :run && call.receiver.is_a?(Prism::ConstantReadNode) && call.receiver.name == :TenantExample
    end
  end

  def self.collect(source)
    AroundCollector.new.tap { Prism.parse(source).value.accept(_1) }
  end

  def self.spec_files
    Dir[Rails.root.join("{spec,packs/*/spec}/**/*.rb")].sort.map { Pathname(_1).relative_path_from(Rails.root).to_s }
  end

  it "Tenancy.with_tenant かトランザクションで example を直に包む around が無い" do
    collected = self.class.spec_files.to_h { [ _1, self.class.collect(Rails.root.join(_1).read) ] }
    wrapping = collected.flat_map { |path, found| found.wrapping.map { "#{path}:#{_1}" } }

    aggregate_failures do
      # 対照：合成のソースの直に包む形は、4 つとも捕まる
      [
        DIRECT_AROUND,
        "around { |example| ActiveRecord::Base.transaction { example.run } }",
        "prepend_around { |example| Tenancy.with_tenant(tenant.id) { example.run } }",
        "append_around do |example|\n  Tenancy.with_tenant(tenant.id) { example.run }\nend"
      ].each { |source| expect(self.class.collect(source).wrapping).to eq([ 1 ]), source }
      # 対照：packs/*/spec の glob が読めている。このファイルの内側の group だけでは満たさない
      expect(collected.select { |path, _| path.start_with?("packs/") }.values.sum { _1.tenant_examples.size }).to be >= 1

      expect(wrapping).to eq([]), "TenantExample.run を通さずに example を包む around：\n#{wrapping.join("\n")}"
    end
  end

  # 内側の group を流し、落ちた example の後に両方の接続にトランザクションが残るか、後ろのグループがポリシーを足し外しできるかを見る
  describe "落ちた example の後の巻き戻し" do
    # 内側の example のトランザクションだけを見るので、この example は包まない
    self.use_transactional_tests = false

    def open_transactions
      [ ActiveRecord::Base, OwnerConnection ].map { _1.connection_pool.with_connection(&:open_transactions) }
    end

    # group.run は実行の絞り込み（-e など）を内側の example にも掛けるので、example を直接走らせる
    def run_inner_group(&body)
      group = RSpec.describe("内側の文脈", &body)
      RSpec.world.example_groups.delete(group)
      group.examples.map do |example|
        @inner_instances << group.new(example.inspect_output)
        example.run(@inner_instances.last, RSpec::Core::NullReporter)
        [ example.execution_result.status, (example.execution_result.exception || example.execution_result.pending_exception)&.message ]
      end
    end

    # 世界を作らずに、後ろのグループが所有ロールの接続でポリシーを足し外しできるかを見る
    def with_policies_result
      MatrixCrossRead.with_policies { nil }
      :ok
    rescue RuntimeError => e
      e.message
    end

    before do
      OwnerConnection.connection_pool.with_connection { nil }
      @inner_instances = []
    end

    # 送出で飛んだ内側の example の後始末を流す。rspec-rails の after_teardown は、トランザクションを巻き戻すだけでなく、
    # example の間だけスレッドをまたいで共有させた接続（ActiveRecord::TestFixtures の pin_connection!）も戻す。
    # 戻さないと、後ろの競合テストの 2 つのスレッドが同じ接続を使い、互いのロックを待って止まる。
    # 後始末を終えた example では、巻き戻す接続の一覧が空なので何もしない
    after do
      @inner_instances.reverse_each(&:after_teardown)
      [ ActiveRecord::Base, OwnerConnection ].each do |model|
        model.connection_pool.with_connection { |connection| connection.rollback_transaction while connection.transaction_open? }
      end
    end

    it "(i) 対照：Tenancy.with_tenant で直に包むと、落ちた example の後に両方の接続にトランザクションが残り、ポリシーを足し外しできない" do
      results = run_inner_group do
        module_eval(DIRECT_AROUND)

        it("SQL のエラーで落ちる") { ActiveRecord::Base.lease_connection.execute("SELECT 1 / 0") }
      end

      # example.run の前の送出ではなく、落ちた example の後にセーブポイントを解放できずに送出した経路を通った
      expect(results).to match([ [ :failed, /division by zero.*current transaction is aborted/m ] ])
      expect(open_transactions).to eq([ 1, 1 ])
      expect(with_policies_result).to include("所有ロールの接続にトランザクションが残っている")
    end

    it "(ii) TenantExample.run で包むと、落ちた example を失敗として出し、後ろの example と後ろのグループに巻き戻しを残さない" do
      seen = []
      record = -> { seen << [ open_transactions, Current.tenant_id.present? ] }

      results = run_inner_group do
        around { |example| TenantExample.run(example, SecureRandom.uuid) }

        it("SQL のエラーで落ちる") { ActiveRecord::Base.lease_connection.execute("SELECT 1 / 0") }
        it("次の example") { record.call }
      end

      # SQL のエラーを飲み込まない
      expect(results).to match([ [ :failed, /division by zero/ ], [ :passed, nil ] ])
      # 対照：次の example の中では、example のトランザクションと with_tenant のセーブポイントの 2 段が開き、テナントが設定されている
      expect(seen).to eq([ [ [ 2, 1 ], true ] ])
      expect(open_transactions).to eq([ 0, 0 ])
      expect(with_policies_result).to eq(:ok)
    end

    it "(iii) TenantExample.run で包んだ pending の example が SQL のエラーで落ちても、pending として出し、巻き戻しを残さない" do
      results = run_inner_group do
        around { |example| TenantExample.run(example, SecureRandom.uuid) }

        it("SQL のエラーで落ちる") do
          pending "落ちることを待つ"
          ActiveRecord::Base.lease_connection.execute("SELECT 1 / 0")
        end
      end

      expect(results).to match([ [ :pending, /division by zero/ ] ])
      expect(open_transactions).to eq([ 0, 0 ])
      expect(with_policies_result).to eq(:ok)
    end

    it "(iv) TenantExample.run で包んだ通る example の後は、after_commit が走り、after_rollback は走らない" do
      ran = []

      results = run_inner_group do
        around { |example| TenantExample.run(example, SecureRandom.uuid) }

        it("コールバックを登録して通る") do
          ApplicationRecord.current_transaction.after_commit { ran << :commit }
          ApplicationRecord.current_transaction.after_rollback { ran << :rollback }
        end
      end

      expect(results).to eq([ [ :passed, nil ] ])
      expect(ran).to eq([ :commit ])
    end
  end
end
