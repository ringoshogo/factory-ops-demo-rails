require "rails_helper"

# 競合テストが後始末（delete_owned_rows）を終えずに終わると、その example が落ちる（docs/guides/testing.md「競合テスト」）。
# ガードは example の後の設定の after で落とし、expect で捕まえられないので、内側の example group を走らせて結果を見る
RSpec.describe "競合テストの後始末のガード" do
  # この spec も競合テストの置き場にあるのでガードを受ける。行を作らないので、存在しないテナントで後始末を終える
  after { delete_owned_rows([ SecureRandom.uuid ], []) }

  # group.run は実行の絞り込み（-e など）を内側の example にも掛けるので、example を直接走らせる
  def run_inner_group(&body)
    group = RSpec.describe("内側の競合テスト", :concurrency, &body)
    RSpec.world.example_groups.delete(group)
    group.examples.map do |example|
      example.run(group.new(example.inspect_output), RSpec::Core::NullReporter)
      [ example.execution_result.status, example.execution_result.exception&.message ]
    end
  end

  it "after で後始末を終えた example は通る" do
    results = run_inner_group do
      after { delete_owned_rows([ SecureRandom.uuid ], []) }

      it("操作する") { expect(1).to eq(1) }
    end

    expect(results).to eq([ [ :passed, nil ] ])
  end

  it "後始末を呼ばない example は落ちる" do
    results = run_inner_group do
      it("操作する") { expect(1).to eq(1) }
    end

    expect(results).to match([ [ :failed, /後始末（delete_owned_rows）を終えていない/ ] ])
  end

  it "after があっても、後始末を終えなければ落ちる" do
    results = run_inner_group do
      after { finish_concurrent_threads }

      it("操作する") { expect(1).to eq(1) }
    end

    expect(results).to match([ [ :failed, /後始末（delete_owned_rows）を終えていない/ ] ])
  end

  it "後始末を終えた印は example ごとに下ろす" do
    results = run_inner_group do
      it("本文で後始末を終える") { delete_owned_rows([ SecureRandom.uuid ], []) }
      it("後始末を呼ばない") { expect(1).to eq(1) }
    end

    expect(results).to match([ [ :passed, nil ], [ :failed, /後始末（delete_owned_rows）を終えていない/ ] ])
  end
end
