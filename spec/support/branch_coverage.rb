# 標準の Coverage で分岐の通過を測り、計測の対象のファイルごとの結果を JSON に書く（docs/guides/testing.md「分岐の網羅率の警告」）。
# bin/check-branch-coverage が、この JSON と git diff を照らす。
#
# 結果の形は、ルートからの相対のパスをキーにし、分岐の腕ごとに種類・開始と終わりの行と列・通過の回数を持つ配列を値にする。
#   { "packs/sales/app/public/sales/catalog.rb" => [ { "type" => "then", "start_line" => 37, "start_column" => 6,
#     "end_line" => 37, "end_column" => 60, "count" => 0 }, ... ] }
# 読み込まれなかったファイルはキーに出ない。分岐の無いファイルは空の配列で出る
require "coverage"
require "json"
require "yaml"
require "fileutils"

module BranchCoverage
  OUTPUT = "tmp/coverage.json"
  TARGETS = YAML.load_file(File.expand_path("../../config/branch_coverage.yml", __dir__)).fetch("targets").freeze

  # 前の実行の結果を消してから測り始める。途中で止まった実行の後に、古い結果を読ませないためである
  def self.start(root:)
    @root = File.realpath(root)
    FileUtils.rm_f(File.join(@root, OUTPUT))
    Coverage.start(branches: true)
  end

  def self.write
    results = Coverage.result.filter_map do |path, coverage|
      relative = relative_path(path)
      [ relative, arms(coverage.fetch(:branches, {})) ] if relative && target?(relative)
    end
    output = File.join(@root, OUTPUT)
    FileUtils.mkdir_p(File.dirname(output))
    File.write(output, JSON.pretty_generate(results.sort.to_h))
  end

  def self.target?(relative) = TARGETS.any? { File.fnmatch?(_1, relative, File::FNM_PATHNAME) }

  def self.relative_path(path)
    real = File.realpath(path)
    real.delete_prefix("#{@root}/") if real.start_with?("#{@root}/")
  rescue SystemCallError
    nil
  end

  # Coverage は分岐を { 条件の座標 => { 腕の座標 => 回数 } } で返す。座標は [種類, 番号, 開始の行, 開始の列, 終わりの行, 終わりの列]
  def self.arms(branches)
    branches.values.flat_map do |targets|
      targets.map do |(type, _id, start_line, start_column, end_line, end_column), count|
        { "type" => type.to_s, "start_line" => start_line, "start_column" => start_column,
          "end_line" => end_line, "end_column" => end_column, "count" => count }
      end
    end.sort_by { [ _1["start_line"], _1["start_column"], _1["type"] ] }
  end
  private_class_method :target?, :relative_path, :arms
end
