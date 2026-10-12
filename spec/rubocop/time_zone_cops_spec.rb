require "json"
require "open3"

# 業務の今日はアプリの時刻帯（config.time_zone）の Date.current・Time.current で決め、システムの時刻帯で決まる呼び出しを
# Cop が落とす（docs/guides/config.md「application.rb で変えたこと」）。.rubocop.yml から外すと、どちらの Cop も黙る
RSpec.describe "時刻帯を混ぜる呼び出しの Cop" do
  root = File.expand_path("../..", __dir__)

  # パッケージのコードの置き場のファイルとして読ませ、出た違反のうち 2 つの Cop の名前を返す。
  # --only で絞らない。--only は .rubocop.yml で無効にした Cop も動かすので、設定から外しても落ちなくなる
  def offenses(root, source)
    output, status = Open3.capture2e(File.join(root, "bin/rubocop"), "--format", "json",
      "--stdin", "packs/sales/app/models/sales/time_zone_example.rb", stdin_data: source, chdir: root)
    raise output unless status.success? || status.exitstatus == 1

    JSON.parse(output).fetch("files").flat_map { _1.fetch("offenses") }.map { _1.fetch("cop_name") }
      .select { %w[Rails/Date Rails/TimeZone].include?(_1) }
  end

  it "Date.today・Time.now・Time.parse を落とす" do
    source = "x = Date.today\ny = Time.now\nz = Time.parse(\"2026-10-12 00:00\")\n"

    expect(offenses(root, source)).to eq([ "Rails/Date", "Rails/TimeZone", "Rails/TimeZone" ])
  end

  it "Date.current・Time.current・Time.zone.parse は通す" do
    source = "x = Date.current\ny = Time.current\nz = Time.zone.parse(\"2026-10-12 00:00\")\n"

    expect(offenses(root, source)).to eq([])
  end
end
