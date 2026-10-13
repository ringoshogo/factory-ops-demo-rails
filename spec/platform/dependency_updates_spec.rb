require "rails_helper"
require "json"
require "yaml"

# 依存の版と Dependabot の更新のまとめ方を守る（docs/guides/config.md「CI の工程」）
RSpec.describe "依存の更新" do
  def self.package = JSON.parse(Rails.root.join("frontend/package.json").read)

  def self.workflow = YAML.load_file(Rails.root.join(".github/workflows/ci.yml"))

  def self.dependabot = YAML.load_file(Rails.root.join(".github/dependabot.yml"))

  def self.major(version) = version.to_s[/\A\D*(\d+)/, 1]&.to_i

  # 画面の Node の主版は engines が正本である。実行（CI・イメージ）と型定義（@types/node）の主版がずれると、
  # 片方でだけ通る API が残る。比べる先は 1 つでも漏らすと、そこがずれても通るので、setup-node のステップはすべて拾う
  describe "画面の Node の主版" do
    def self.engines_major = major(package.dig("engines", "node"))

    it "engines は ^<主版>.<小版> の形で、主版を 1 つに決める" do
      expect(self.class.package.dig("engines", "node")).to match(/\A\^\d+\.\d+\z/)
    end

    it "CI の actions/setup-node を使うすべてのステップの node-version が、engines と同じ主版である" do
      steps = self.class.workflow.fetch("jobs").values.flat_map { _1.fetch("steps") }
        .select { _1["uses"].to_s.start_with?("actions/setup-node@") }

      expect(steps).not_to be_empty
      expect(steps.map { self.class.major(_1.dig("with", "node-version")) }).to all(eq(self.class.engines_major))
    end

    it "frontend/Dockerfile の NODE_VERSION が、engines と同じ主版である" do
      node_version = Rails.root.join("frontend/Dockerfile").read[/^ARG NODE_VERSION=(\S+)$/, 1]

      expect(self.class.major(node_version)).to eq(self.class.engines_major)
    end

    it "@types/node の範囲が、engines と同じ主版である" do
      expect(self.class.major(self.class.package.dig("devDependencies", "@types/node"))).to eq(self.class.engines_major)
    end
  end

  # 1 つの依存に 1 本の PR では、組で上げる依存が 1 本ずつでは落ち、PR のたびに images のジョブが流れる。
  # 主版の上げは破壊的な変更を含みうるので、まとめずに 1 本ずつ CI で確かめる
  describe "Dependabot のまとめ方" do
    def self.updates = dependabot.fetch("updates")

    def self.ecosystem(name) = updates.find { _1["package-ecosystem"] == name } || raise("dependabot.yml に #{name} が無い")

    # 小版と修正版のまとまりは、すべての依存（*）を拾うまとまりである
    def self.catch_all_group(name)
      ecosystem(name).fetch("groups", {}).find { |_, group| Array(group["patterns"]).include?("*") }&.last || {}
    end

    def self.paired = %w[react react-dom @types/react @types/react-dom]

    it "どのエコシステムも groups を持つ" do
      expect(self.class.updates).to all(include("groups"))
    end

    it "bundler と npm の小版と修正版のまとまりは、update-types が minor と patch だけである" do
      update_types = %w[bundler npm].to_h { [ _1, Array(self.class.catch_all_group(_1)["update-types"]).sort ] }

      expect(update_types).to eq("bundler" => %w[minor patch], "npm" => %w[minor patch])
    end

    # Dependabot は、依存を最初に当たったまとまりに入れる
    it "npm の組の依存のまとまりは、組の 4 つを patterns に持ち、小版と修正版のまとまりより先にある" do
      groups = self.class.ecosystem("npm").fetch("groups", {}).to_a
      paired_index = groups.index { |_, group| (self.class.paired - Array(group["patterns"])).empty? }
      catch_all_index = groups.index { |_, group| Array(group["patterns"]).include?("*") }

      expect(paired_index).not_to be_nil
      expect(catch_all_index).not_to be_nil
      expect(paired_index).to be < catch_all_index
    end

    # 0 系の小版の上げは破壊的な変更を含みうるので、主版の上げと同じく 1 本ずつ開かせる。
    # 0 系の依存は、まとめ方の設定からではなく package.json の範囲から集める
    it "画面の 0 系の依存は、npm の小版と修正版のまとまりの exclude-patterns にある" do
      zero_major = self.class.package.values_at("dependencies", "devDependencies").reduce(:merge)
        .select { |_, range| self.class.major(range) == 0 }.keys

      expect(zero_major).not_to be_empty
      expect(zero_major - Array(self.class.catch_all_group("npm")["exclude-patterns"])).to eq([])
    end

    it "github-actions のまとまりは、主版を含めてすべての action（*）を持つ" do
      expect(self.class.catch_all_group("github-actions")).to include("patterns" => [ "*" ])
      expect(self.class.catch_all_group("github-actions")).not_to include("update-types")
    end

    it "@types/node の主版の上げは ignore にある" do
      ignore = self.class.ecosystem("npm").fetch("ignore", [])

      expect(ignore).to include(
        a_hash_including("dependency-name" => "@types/node", "update-types" => [ "version-update:semver-major" ])
      )
    end
  end
end
