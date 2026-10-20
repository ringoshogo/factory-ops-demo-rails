require "rails_helper"
require "yaml"

# CI のワークフローが流す bin/ の検査は、実装者が手元で流す「共通の完了条件」と bin/ci の工程にもある
# （docs/implementation-plan.md「共通の完了条件」、docs/guides/config.md「CI の工程」）。
# 実装者は完了条件の一覧のとおりに流すので、一覧に無い検査は、PR を出してから CI で初めて落ちる。
# 照らすのはコマンドの名前だけで、引数と BASE_REF の式は照らさない
RSpec.describe "CI と手元で流す検査" do
  def self.bin_commands(text) = text.scan(%r{(?<![\w/.-])bin/[a-z][a-z-]*}).uniq.sort

  def self.workflow = YAML.load_file(Rails.root.join(".github/workflows/ci.yml"))

  # publish の if: に許す式は 1 つで、書き方の違いは前後の空白・全体を囲む ${{ }}・続く空白だけをそろえる
  # （docs/guides/config.md「CI の工程」）。大文字と小文字・括弧・引用符はそろえない。GitHub は関数の名前の大小を区別しないと
  # みられ（actions/runner のソースからの推定）、括弧と引用符は式の意味を変えるので、そろえると迂回を通す
  def self.publish_condition = "success() && github.event_name == 'push'"

  def self.publish_condition?(condition)
    stripped = condition.strip
    stripped = stripped[/\A\$\{\{(.*)\}\}\z/m, 1] || stripped
    stripped.strip.gsub(/\s+/, " ") == publish_condition
  end

  def self.workflow_commands
    bin_commands(workflow.fetch("jobs").values.flat_map { _1.fetch("steps") }.filter_map { _1["run"] }.join("\n"))
  end

  def self.completion_block
    plan = Rails.root.join("docs/implementation-plan.md").read
    section = plan[/^### 共通の完了条件\n(.*?)^#/m, 1] or raise "implementation-plan.md に「共通の完了条件」の節が無い"
    section[/^```sh\n(.*?)^```/m, 1].to_s
  end

  def self.completion_commands = bin_commands(completion_block)

  # パスを付けない（全件を流す）bundle exec rspec ごとの、前置きの環境変数。spec のパスは spec/ か packs/ で始まる
  def self.full_rspec_envs(text)
    text.split(/&&|\n/).filter_map do |command|
      words = command.split
      index = words.each_cons(3).find_index { _1 == %w[bundle exec rspec] }
      next unless index && words.drop(index + 3).none? { _1.match?(%r{\A(\./)?(spec|packs)/}) }

      words.take(index).to_h { _1.split("=", 2) }
    end
  end

  it "ワークフローが流す bin/ の検査は、すべて共通の完了条件にある" do
    expect(self.class.workflow_commands - self.class.completion_commands).to eq([])
  end

  it "ワークフローが流す bin/ の検査は、すべて bin/ci の工程にある" do
    expect(self.class.workflow_commands - self.class.bin_commands(Rails.root.join("config/ci.rb").read)).to eq([])
  end

  # npm ci は直接の依存の peer の不一致しか止めず、入れ子の依存の peer の範囲から外れた更新は npm ls --all でだけ見える
  # （docs/guides/config.md「CI の工程」）。npm ls は npm ci が frontend に入れた木を読むので、同じ置き場で npm ci の後に流す。
  # 失敗でジョブを落とすこと（continue-on-error を持たないこと）は、publish の needs の example がすべてのステップで確かめる
  it "frontend のジョブは、npm ci の後に、同じ frontend の置き場で npm ls --all を必ず流す" do
    job = self.class.workflow.dig("jobs", "frontend")
    steps = job.fetch("steps")
    commands = steps.filter_map { _1["run"]&.strip }
    directory = ->(command) do
      step = steps.find { _1["run"]&.strip == command }
      step && (step["working-directory"] || job.dig("defaults", "run", "working-directory"))
    end

    expect(commands.drop_while { _1 != "npm ci" }.drop(1)).to include("npm ls --all")
    expect([ "npm ci", "npm ls --all" ].map(&directory)).to eq(%w[frontend frontend])
    expect(steps.find { _1["run"]&.strip == "npm ls --all" }).not_to have_key("if")
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
  # 期待するジョブは publish の needs からではなく、ワークフローの jobs から集める。continue-on-error は、ジョブの段では
  # そのジョブが落ちても needs の結果を、ステップの段ではそのステップが落ちてもジョブの結果を success にするので、
  # publish がそのジョブかステップの成功を待たなくなる
  it "publish の needs は、ほかのすべてのジョブちょうどで、continue-on-error を持つジョブとステップは無い" do
    jobs = self.class.workflow.fetch("jobs")
    continuing = jobs.select { |_, job| job.key?("continue-on-error") }.keys +
      jobs.flat_map { |name, job| job.fetch("steps").select { _1.key?("continue-on-error") }.map { "#{name}: #{_1['name']}" } }

    expect(Array(jobs.dig("publish", "needs")).sort).to eq((jobs.keys - %w[publish]).sort)
    expect(continuing).to eq([])
  end

  # どのジョブも PR と main への push のたびに流れ、publish だけが main への push で、ほかのすべてのジョブの成功を待って流れる
  # （docs/guides/config.md「CI の工程」）。ほかのジョブに契機を絞る if: を足すと、push でそのジョブが skip され、
  # publish も skip されてイメージが置かれなくなる。publish の if: は、needs のどれかが落ちた・取り消された・skip されたときに
  # 偽になる 1 つの式にちょうど一致させて照らし、落とす迂回の形は並べない。式を変える人は publish_condition も直す
  it "ジョブの段の if: を持つのは publish だけで、publish の if: は success() && github.event_name == 'push' に一致する" do
    jobs = self.class.workflow.fetch("jobs")

    expect(jobs.select { |_, job| job.key?("if") }.keys).to eq(%w[publish])
    expect(self.class.publish_condition?(jobs.dig("publish", "if").to_s)).to be(true)
  end

  # 照らし方の表。落とす行は、needs が落ちても流れる迂回（否定・論理和・比べ・関数の引数と添字・大文字の状態の関数と
  # 文字列の中の success()）と、needs が落ちれば偽になるが一致しない式（項の順か大小が違う）である
  rejected = [
    "${{ !success() && github.event_name == 'push' }}",
    "${{ !(success() && github.event_name == 'push') }}",
    "success() || github.event_name == 'push'",
    "success() == false && github.event_name == 'push'",
    "false == success() && github.event_name == 'push'",
    "success() >= false && github.event_name == 'push'",
    "success() < 1 && github.event_name == 'push'",
    "1 > success() && github.event_name == 'push'",
    "format('{0}', success()) && github.event_name == 'push'",
    "toJSON(success()) && github.event_name == 'push'",
    "contains('truefalse', success()) && github.event_name == 'push'",
    "format('){0}', success()) && github.event_name == 'push'",
    "format('{0}{1}', toJSON(github.event_name), success()) && github.event_name == 'push'",
    "join(fromJSON('[1]'), success()) && github.event_name == 'push'",
    "fromJSON('[1,1]')[success()] && github.event_name == 'push'",
    "${{ 'success()' && Always() }}",
    "${{ Always() && github.event_name == 'push' && 'success()' }}",
    "${{ Failure() && 'success()' }}",
    "success() && github.event_name == 'push' || always()",
    "always() || github.event_name == 'push' && success()",
    "${{ github.event_name == 'push' && success() }}",
    "Success() && github.event_name == 'push'"
  ]

  accepted = [
    "success() && github.event_name == 'push'",
    "${{ success() && github.event_name == 'push' }}",
    "  success()  &&  github.event_name == 'push'  "
  ]

  rejected.each do |condition|
    it "publish の if: の照らし方は #{condition} を落とす" do
      expect(self.class.publish_condition?(condition)).to be(false)
    end
  end

  accepted.each do |condition|
    it "publish の if: の照らし方は #{condition.inspect} を通す" do
      expect(self.class.publish_condition?(condition)).to be(true)
    end
  end

  # 全件の流れでだけ、どの spec も呼ばなかった公開 API で落とす（spec/support/public_api_returns.rb）。全件を流す場所のどれかが
  # 印を渡さないと、そこでは呼ばれない公開 API が黙って残る。名指しした場所だけを照らすと、ほかの場所を書き換えても落ちないので、
  # 3 つの置き場からパスを付けない rspec をすべて集める。ワークフローの印は、ワークフロー・ジョブ・ステップの env のどれでもよい
  it "全件を流す rspec は、ワークフロー・bin/ci の工程・共通の完了条件のどれでも、全件の印 FULL_SUITE=1 を渡す" do
    workflow = self.class.workflow
    workflow_envs = workflow.fetch("jobs").values.flat_map do |job|
      job.fetch("steps").flat_map do |step|
        self.class.full_rspec_envs(step["run"].to_s).map do |prefix|
          [ workflow["env"], job["env"], step["env"] ].compact.reduce({}, :merge).transform_values(&:to_s).merge(prefix)
        end
      end
    end
    marks = {
      "workflow" => workflow_envs,
      "config/ci.rb" => self.class.full_rspec_envs(Rails.root.join("config/ci.rb").read),
      "共通の完了条件" => self.class.full_rspec_envs(self.class.completion_block)
    }.transform_values { |envs| envs.map { _1["FULL_SUITE"] }.uniq }

    expect(marks).to eq("workflow" => [ "1" ], "config/ci.rb" => [ "1" ], "共通の完了条件" => [ "1" ])
  end

  it "全件を流す rspec を、spec のパスを付けたものと分け、前置きの環境変数を拾う" do
    text = "bin/rails db:test:prepare && COVERAGE=1 FULL_SUITE=1 bundle exec rspec --format json --out tmp/rspec.json\n" \
      "bundle exec rspec spec/platform\nbundle exec rspec ./packs/sales/spec\nbundle exec rspec\n"

    expect(self.class.full_rspec_envs(text)).to eq([ { "COVERAGE" => "1", "FULL_SUITE" => "1" }, {} ])
  end

  it "コマンドの名前を、引数と前置きの環境変数を除いて拾う" do
    text = "BASE_REF=origin/main bin/check-branch-coverage\nbin/rails db:test:prepare && bin/packwerk check\n./bin/thrust ./bin/rails server\n"

    expect(self.class.bin_commands(text)).to eq(%w[bin/check-branch-coverage bin/packwerk bin/rails])
  end
end
