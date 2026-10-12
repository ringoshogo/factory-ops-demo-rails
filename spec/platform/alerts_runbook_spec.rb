require "rails_helper"
require "yaml"

# どの警報からも手順書へたどれる（docs/slo.md「警報と手順書」）。警報の規則は annotations.runbook に docs/runbooks/ の
# 手順書のパスを持ち、そのファイルがある。手順書は、警報を受けた人が上から読む順の節を持つ
RSpec.describe "警報と手順書" do
  RUNBOOK_SECTIONS = %w[警報 確かめること 止血 復旧 事後にすること].freeze

  def self.alerts
    path = Rails.root.join("config/prometheus/alerts.yml")
    return [] unless path.exist?

    YAML.load_file(path).fetch("groups").flat_map { _1.fetch("rules") }.select { _1.key?("alert") }
  end

  def self.runbooks = Dir[Rails.root.join("docs/runbooks/*.md")].sort

  it "警報の規則がある" do
    expect(self.class.alerts).not_to be_empty
  end

  it "どの警報も、docs/runbooks/ にある手順書のパスを runbook に持つ" do
    missing = self.class.alerts.reject do |rule|
      path = rule.dig("annotations", "runbook").to_s
      path.match?(%r{\Adocs/runbooks/[a-z0-9-]+\.md\z}) && Rails.root.join(path).file?
    end

    expect(missing.map { _1["alert"] }).to eq([])
  end

  it "どの手順書も、いずれかの警報から指される" do
    linked = self.class.alerts.map { _1.dig("annotations", "runbook") }.uniq
    runbooks = self.class.runbooks.map { Pathname(_1).relative_path_from(Rails.root).to_s }

    expect(runbooks).not_to be_empty
    expect(runbooks - linked).to eq([])
  end

  it "どの手順書も、警報・確かめること・止血・復旧・事後にすることの節をこの順に持つ" do
    out_of_order = self.class.runbooks.reject do |path|
      File.read(path).scan(/^## (.+)$/).flatten.select { RUNBOOK_SECTIONS.include?(_1) } == RUNBOOK_SECTIONS
    end

    expect(self.class.runbooks).not_to be_empty
    expect(out_of_order).to eq([])
  end
end
