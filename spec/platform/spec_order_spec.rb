require "rails_helper"
require "json"
require "open3"

# spec は乱順で流れ、落ちたときは出力の seed を --seed に渡すと同じ順で流れ直す（docs/guides/testing.md「層への配分」）。
# 親のプロセスの設定は読まない。rspec-core 3.13.6 はコマンドラインの --seed と --order を設定ファイルより優先する
# （lib/rspec/core/configuration_options.rb の force? と、lib/rspec/core/ordering.rb の ConfigurationManager#force）ので、
# --seed を渡して流す親では、spec/spec_helper.rb の設定を注釈に戻しても乱順のまま通るからである。
# 子は --options .rspec で流し、~/.rspec と .rspec-local を読ませない。親の SPEC_OPTS・COVERAGE・FULL_SUITE も渡さない
RSpec.describe "spec を流す順" do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  def run_examples(*args, rand_file: nil)
    out = File.join(@dir, "examples.json")
    env = { "SPEC_OPTS" => nil, "COVERAGE" => nil, "FULL_SUITE" => nil, "SPEC_ORDER_RAND_FILE" => rand_file }
    output, status = Open3.capture2e(env, "bundle", "exec", "rspec", "--options", ".rspec", "spec/fixtures/spec_order/examples.rb",
      *args, "--format", "json", "--out", out, chdir: Rails.root.to_s)
    raise "子のプロセスが #{status.exitstatus} で終わった:\n#{output}" unless status.success?

    JSON.parse(File.read(out))
  end

  def order(json) = json.fetch("examples").map { _1.fetch("description") }

  def rand_with_seed(seed)
    file = File.join(@dir, "rand.txt")
    run_examples("--seed", seed.to_s, rand_file: file)
    File.read(file)
  end

  it "順も seed も渡さずに流すと乱順で並べ、出力の seed を渡すと同じ並びと同じ Kernel.rand で流れ直す" do
    # (a) json_formatter.rb は、乱順で並べたときだけ seed を出す
    chosen = run_examples("--dry-run")
    expect(chosen["seed"]).to be_a(Integer)

    # (b) 選ばれた seed は、定義の順と同じ並びを引くこともあるので、並びが定義の順と違うかはここでは見ない
    expect(order(run_examples("--seed", chosen["seed"].to_s, "--dry-run"))).to eq(order(chosen))

    # (c) rspec の乱順は Kernel.rand を使わないので、Kernel.srand が seed で種を蒔いたかは別に確かめる
    expect(rand_with_seed(chosen["seed"])).to eq(rand_with_seed(chosen["seed"]))
  end

  # seed 1 は、10 個の example を定義の順と違う並びにする
  it "seed で並べた順は、定義の順と違う" do
    defined = order(run_examples("--order", "defined", "--dry-run"))

    expect(defined).to eq((1..10).map(&:to_s))
    expect(order(run_examples("--seed", "1", "--dry-run"))).not_to eq(defined)
  end
end
