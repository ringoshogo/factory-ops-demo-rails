# bin/test-layers が rspec の JSON の出力を層に分けて報告し、未分類のファイルを止めることを確かめる
# （docs/guides/testing.md「テストの層」）
require "json"
require "open3"
require "tmpdir"

RSpec.describe "bin/test-layers" do
  let(:script) { File.expand_path("../../bin/test-layers", __dir__) }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def example_at(id, run_time: 0.1, file_path: nil)
    { "id" => id, "file_path" => file_path || id[/\A[^\[]+/], "run_time" => run_time, "status" => "passed" }
  end

  def run_layers(examples, env: {})
    json = File.join(@dir, "rspec.json")
    File.write(json, JSON.generate("examples" => examples))
    Open3.capture3(env, script, json)
  end

  def units(count) = Array.new(count) { |i| example_at("./packs/sales/spec/public/sales/x_spec.rb[1:#{i + 1}]") }

  it "層ごとの件数・割合・時間を表にし、ガードを割合に数えない" do
    examples = [
      *units(7),
      example_at("./spec/requests/catalog_spec.rb[1:1]", run_time: 0.5),
      example_at("./spec/contracts/publish_spec.rb[1:1]", run_time: 0.25),
      example_at("./spec/scenarios/tenant_boundary_spec.rb[1:1]", run_time: 2.0),
      example_at("./spec/matrix/table_matrix_spec.rb[1:1]"),
      example_at("./spec/matrix/table_matrix_spec.rb[1:2]")
    ]

    out, err, status = run_layers(examples)

    expect([ err, status.success? ]).to eq([ "", true ])
    expect(out).to include("| 単体 | 7 | 70.0% | 0.70s | — |")
    expect(out).to include("| 結合 | 2 | 20.0% | 0.75s | — |")
    expect(out).to include("| シナリオ | 1 | 10.0% | 2.00s | 50% 以下 |")
    expect(out).to include("| ガード | 2 | — | 0.20s | 数えない |")
    expect(out).not_to include("::warning::")
  end

  it "層は id のファイルの部分で決め、共有の example を定義したファイル（file_path）を見ない" do
    shared = example_at("./spec/requests/catalog_spec.rb[1:1:1]", file_path: "./spec/support/shared_examples/idempotent_receiver.rb")

    out, _err, status = run_layers([ *units(9), shared ])

    expect(status.success?).to be(true)
    expect(out).to include("| 結合 | 1 | 10.0% |")
  end

  it "パッケージの concurrency の置き場はシナリオに数え、単体に数えない" do
    out, _err, status = run_layers([ *units(9), example_at("./packs/inventory/spec/concurrency/stock_lock_spec.rb[1:1]") ])

    expect(status.success?).to be(true)
    expect(out).to include("| 単体 | 9 | 90.0% |", "| シナリオ | 1 | 10.0% |")
  end

  it "どの層の置き場にも当たらないファイルがあれば、そのファイルを示して失敗する" do
    _out, err, status = run_layers([ *units(1), example_at("./spec/models/stray_spec.rb[1:1]") ])

    expect(status.success?).to be(false)
    expect(err).to include("spec/models/stray_spec.rb")
  end

  it "割合が目安を外れたら警告の注釈を出し、失敗にはしない" do
    examples = [ *units(4), *Array.new(6) { |i| example_at("./spec/scenarios/tenant_boundary_spec.rb[1:#{i + 1}]") } ]

    out, _err, status = run_layers(examples)

    expect(status.success?).to be(true)
    expect(out).to include("::warning::シナリオの割合 60.0% が目安（50% 以下）を外れた")
    expect(out.scan("::warning::").size).to eq(1)
  end

  it "目安を持たない層は、割合が偏っても警告を出さない" do
    examples = [ *units(1), *Array.new(9) { |i| example_at("./spec/requests/catalog_spec.rb[1:#{i + 1}]") } ]

    out, _err, status = run_layers(examples)

    expect(status.success?).to be(true)
    expect(out).to include("| 結合 | 9 | 90.0% |")
    expect(out).not_to include("::warning::")
  end

  it "GITHUB_STEP_SUMMARY があれば、同じ表を書き足す" do
    summary = File.join(@dir, "summary.md")
    File.write(summary, "前の工程\n")

    run_layers(units(1), env: { "GITHUB_STEP_SUMMARY" => summary })

    expect(File.read(summary)).to start_with("前の工程\n").and include("| 単体 | 1 | 100.0% |")
  end
end
