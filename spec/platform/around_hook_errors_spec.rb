require "rails_helper"

# example を包む around のフックが example.run の後に送出しても、example ごとのトランザクションを巻き戻す（spec/support/around_hook_errors.rb）。
# Tenancy.with_tenant で包んだ example が SQL のエラーで落ちると、with_tenant がセーブポイントを解放できずに around から送出する。
# 巻き戻しは rspec-rails のさらに外側の around にあり、送出で飛ぶので、トランザクションが残って後ろの example に入れ子になる。
# 所有ロールの接続に残ると、後ろのグループがポリシーを足し外ししてもコミットされず、表のロックを持ったまま rspec が止まる
RSpec.describe "around のフックが送出したときの example のトランザクションの巻き戻し" do
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
      example.run(group.new(example.inspect_output), RSpec::Core::NullReporter)
      [ example.execution_result.status, example.execution_result.exception&.message ]
    end
  end

  it "Tenancy.with_tenant の around の中で SQL のエラーで落ちた example の後も、アプリと所有ロールの接続にトランザクションを残さない" do
    OwnerConnection.connection_pool.with_connection { nil }
    seen = []
    record = -> { seen << open_transactions }

    results = run_inner_group do
      around { |example| Tenancy.with_tenant(SecureRandom.uuid) { example.run } }

      it("SQL のエラーで落ちる") { ActiveRecord::Base.lease_connection.execute("SELECT 1 / 0") }
      it("次の example") { record.call }
    end

    # around が送出した例外も、飲み込まずに example の失敗として出す
    expect(results).to match([ [ :failed, /division by zero.*current transaction is aborted/m ], [ :passed, nil ] ])
    # 対照：落ちなかった次の example の中では、example のトランザクションと with_tenant のセーブポイントの 2 段が開いている
    expect(seen).to eq([ [ 2, 1 ] ])
    expect(open_transactions).to eq([ 0, 0 ])
  ensure
    [ ActiveRecord::Base, OwnerConnection ].each do |model|
      model.connection_pool.with_connection { |connection| connection.rollback_transaction while connection.transaction_open? }
    end
  end
end
