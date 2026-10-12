require "rails_helper"
require_relative "../support/cross_read"

# 共有の文脈「RLS の SELECT を開く」が、グループの後にポリシーを外し、足すのに失敗したときは、先にあったポリシーを外さない
# （docs/guides/testing.md「行列テストとの分担」）。誤ると、同じテストの DB で行列を流すほかの実行の 2 回目が空振りする
RSpec.describe "共有の文脈「RLS の SELECT を開く」" do
  # ポリシーの足し外しは所有ロールの接続で表のロックを取るので、example ごとのトランザクションの外で走らせる
  self.use_transactional_tests = false

  def cross_read_policies
    ActiveRecord::Base.lease_connection
      .select_value("SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND policyname = 'matrix_cross_read'")
  end

  # 文脈を使う内側の example group を走らせ、example の結果を返す。実行の絞り込みと --order rand を内側に掛けない
  def run_inner_group(&body)
    group = RSpec.describe("内側の文脈", order: :defined) do
      include_context "RLS の SELECT を開く"
      instance_exec(&body)
    end
    RSpec.world.example_groups.delete(group)
    RSpec.world.filtered_examples[group] = group.examples
    group.run(RSpec::Core::NullReporter)
    group.examples.map { [ _1.execution_result.status, _1.execution_result.exception&.message ] }
  end

  it "グループの間だけポリシーを足し、終わったら外す" do
    seen = nil
    count = method(:cross_read_policies)
    results = run_inner_group { it("数える") { seen = count.call } }

    expect(results).to eq([ [ :passed, nil ] ])
    expect(seen).to eq(MatrixWorld.tenant_tables.size)
    expect(cross_read_policies).to eq(0)
  end

  it "同じ名前のポリシーがすでにあれば、足さずに失敗し、あったポリシーを外さない" do
    MatrixCrossRead.add!

    results = run_inner_group { it("走らない") { nil } }

    expect(results.first.last).to include("matrix_cross_read のポリシーがすでにある")
    expect(cross_read_policies).to eq(MatrixWorld.tenant_tables.size)
  ensure
    MatrixCrossRead.remove!
  end
end
