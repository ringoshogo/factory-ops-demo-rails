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

  # npm ci は直接の依存の peer の不一致しか止めず、入れ子の依存の peer の範囲から外れた更新は npm ls --all でだけ見える
  # （docs/guides/config.md「CI の工程」）。npm ls は入れた木を読むので npm ci の後に流し、落ちたらジョブを落とす
  it "frontend のジョブは、npm ci の後に npm ls --all を流し、その失敗でジョブを落とす" do
    steps = self.class.workflow.dig("jobs", "frontend", "steps")
    commands = steps.filter_map { _1["run"]&.strip }
    list_step = steps.find { _1["run"]&.strip == "npm ls --all" }

    expect(commands.drop_while { _1 != "npm ci" }.drop(1)).to include("npm ls --all")
    expect(list_step&.slice("if", "continue-on-error", "working-directory")).to eq({})
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

  # publish は needs の結果だけを見て、ジョブの名前を並べない。needs に無いジョブが落ちても push するので、
  # 期待するジョブは publish の needs からではなく、ワークフローの jobs から集める。ジョブの段の continue-on-error は、
  # そのジョブが落ちても needs の結果を success にするので、publish がそのジョブの成功を待たなくなる
  it "publish の needs は、ほかのすべてのジョブを含み、ジョブの段の continue-on-error を持つジョブは無い" do
    jobs = self.class.workflow.fetch("jobs")

    expect(jobs.keys - %w[publish] - Array(jobs.dig("publish", "needs"))).to eq([])
    expect(jobs.select { |_, job| job.key?("continue-on-error") }.keys).to eq([])
  end

  # どのジョブも PR と main への push のたびに流れ、publish だけが main への push で、ほかのすべてのジョブの成功を待って流れる
  # （docs/guides/config.md「CI の工程」）。ほかのジョブに契機を絞る if: を足すと、そのジョブが確かめないまま push する
  it "ジョブの段の if: を持つのは publish だけ" do
    expect(self.class.workflow.fetch("jobs").select { |_, job| job.key?("if") }.keys).to eq(%w[publish])
  end

  it "コマンドの名前を、引数と前置きの環境変数を除いて拾う" do
    text = "BASE_REF=origin/main bin/check-branch-coverage\nbin/rails db:test:prepare && bin/packwerk check\n./bin/thrust ./bin/rails server\n"

    expect(self.class.bin_commands(text)).to eq(%w[bin/check-branch-coverage bin/packwerk bin/rails])
  end
end
