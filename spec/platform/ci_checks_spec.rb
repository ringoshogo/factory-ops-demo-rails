require "rails_helper"
require "yaml"

# CI のワークフローが流す bin/ の検査は、実装者が手元で流す「共通の完了条件」と bin/ci の工程にもある
# （docs/implementation-plan.md「共通の完了条件」、docs/guides/config.md「CI の工程」）。
# 実装者は完了条件の一覧のとおりに流すので、一覧に無い検査は、PR を出してから CI で初めて落ちる。
# 照らすのはコマンドの名前だけで、引数と BASE_REF の式は照らさない
RSpec.describe "CI と手元で流す検査" do
  def self.bin_commands(text) = text.scan(%r{(?<![\w/.-])bin/[a-z][a-z-]*}).uniq.sort

  def self.workflow = YAML.load_file(Rails.root.join(".github/workflows/ci.yml"))

  def self.workflow_commands
    bin_commands(workflow.fetch("jobs").values.flat_map { _1.fetch("steps") }.filter_map { _1["run"] }.join("\n"))
  end

  def self.completion_commands
    plan = Rails.root.join("docs/implementation-plan.md").read
    section = plan[/^### 共通の完了条件\n(.*?)^#/m, 1] or raise "implementation-plan.md に「共通の完了条件」の節が無い"
    bin_commands(section[/^```sh\n(.*?)^```/m, 1].to_s)
  end

  it "ワークフローが流す bin/ の検査は、すべて共通の完了条件にある" do
    expect(self.class.workflow_commands - self.class.completion_commands).to eq([])
  end

  it "ワークフローが流す bin/ の検査は、すべて bin/ci の工程にある" do
    expect(self.class.workflow_commands - self.class.bin_commands(Rails.root.join("config/ci.rb").read)).to eq([])
  end

  # images のジョブは、PR がイメージに入るものを変えたときだけ流れる（docs/guides/config.md「CI の工程」）。
  # 判定の pattern から漏れたファイルだけを変えた PR は、イメージを組み立てて確かめないまま通る。
  # 対象は Dockerfile とその無視の一覧、Dockerfile が名指しで写すファイル、マニフェストで、ディレクトリごとに写す
  # アプリのコードと画面は test と e2e のジョブが確かめるので含めない
  it "image_inputs の pattern は、Dockerfile・無視の一覧・Dockerfile が名指しで写すファイル・マニフェストに当たる" do
    run = YAML.load_file(Rails.root.join(".github/workflows/ci.yml")).dig("jobs", "image_inputs", "steps").filter_map { _1["run"] }.join
    pattern = Regexp.new(run[/pattern='([^']+)'/, 1] || raise("image_inputs のジョブに pattern が無い"))
    tracked = IO.popen(%w[git ls-files], chdir: Rails.root, &:read).lines(chomp: true)
    dockerfiles = tracked.grep(%r{(\A|/)Dockerfile\z})
    copied = dockerfiles.flat_map do |file|
      Rails.root.join(file).read.scan(/^COPY (?!.*--from)(.+) \S+$/).flatten.flat_map(&:split).reject { _1.start_with?("--") }
    end
    inputs = dockerfiles + tracked.grep(/(\A|\/)(\.dockerignore|Dockerfile\.dockerignore)\z/) + tracked.grep(%r{\Adeploy/}) +
      copied.reject { _1 == "." || _1.end_with?("/", "*") }

    expect(inputs.uniq.reject { pattern.match?(_1) }).to eq([])
  end

  # ubuntu-latest は GitHub が日程で OS の版を上げ、CI が通るかを確かめないまま版が変わる（docs/guides/config.md「CI の工程」）。
  # 版を上げる PR で spec を書き換えずに済むよう、名前は版の形で照らす。公開の配置は arm64 で動くので、
  # イメージを組み立てる 2 つのジョブだけが arm64 のランナーで動く
  it "どのジョブの runs-on も版の数字を含み、arm64 のランナーで動くのはイメージを組み立てるジョブだけ" do
    runners = self.class.workflow.fetch("jobs").transform_values { _1["runs-on"] }

    expect(runners.reject { |_, runner| runner.to_s.match?(/\Aubuntu-\d{2}\.\d{2}(-arm)?\z/) }).to eq({})
    expect(runners.select { |_, runner| runner.to_s.end_with?("-arm") }.keys.sort).to eq(%w[images publish])
  end

  # テストの落ちた commit のイメージを GHCR に置かないため、push は全ジョブの成功を待つ publish にだけ置く。
  # 権限を書かないジョブの権限はリポジトリの設定で決まるので、最上位を読み取りだけにする
  it "イメージを push するジョブと packages: write を持つジョブは publish だけで、最上位の権限は読み取りだけ" do
    jobs = self.class.workflow.fetch("jobs")
    pushes = jobs.select do |_, job|
      job.fetch("steps").any? { _1["run"].to_s.include?("docker push") || _1.dig("with", "push").to_s == "true" }
    end

    expect(pushes.keys).to eq(%w[publish])
    expect(jobs.select { |_, job| job.dig("permissions", "packages") == "write" }.keys).to eq(%w[publish])
    expect(self.class.workflow["permissions"]).to eq("contents" => "read")
  end

  # publish の if: は needs の結果だけを見て、ジョブの名前を並べない。needs に無いジョブが落ちても push するので、
  # 期待するジョブは publish の needs からではなく、ワークフローの jobs から集める。image_inputs は push では skip される
  it "publish の needs は、image_inputs のほかのすべてのジョブを含む" do
    jobs = self.class.workflow.fetch("jobs")

    expect(jobs.keys - %w[image_inputs publish] - Array(jobs.dig("publish", "needs"))).to eq([])
  end

  it "コマンドの名前を、引数と前置きの環境変数を除いて拾う" do
    text = "BASE_REF=origin/main bin/check-branch-coverage\nbin/rails db:test:prepare && bin/packwerk check\n./bin/thrust ./bin/rails server\n"

    expect(self.class.bin_commands(text)).to eq(%w[bin/check-branch-coverage bin/packwerk bin/rails])
  end
end
