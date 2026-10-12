require "rails_helper"
require "yaml"

# CI のワークフローが流す bin/ の検査は、実装者が手元で流す「共通の完了条件」と bin/ci の工程にもある
# （docs/implementation-plan.md「共通の完了条件」、docs/guides/config.md「CI の工程」）。
# 実装者は完了条件の一覧のとおりに流すので、一覧に無い検査は、PR を出してから CI で初めて落ちる。
# 照らすのはコマンドの名前だけで、引数と BASE_REF の式は照らさない
RSpec.describe "CI と手元で流す検査" do
  def self.bin_commands(text) = text.scan(%r{(?<![\w/.-])bin/[a-z][a-z-]*}).uniq.sort

  def self.workflow_commands
    workflow = YAML.load_file(Rails.root.join(".github/workflows/ci.yml"))
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

  it "コマンドの名前を、引数と前置きの環境変数を除いて拾う" do
    text = "BASE_REF=origin/main bin/check-branch-coverage\nbin/rails db:test:prepare && bin/packwerk check\n./bin/thrust ./bin/rails server\n"

    expect(self.class.bin_commands(text)).to eq(%w[bin/check-branch-coverage bin/packwerk bin/rails])
  end
end
