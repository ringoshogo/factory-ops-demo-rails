# bin/check-branch-coverage が、計測の結果と差分を照らして、足した行の未通過の分岐を警告にすることと、
# spec/support/branch_coverage.rb が計測の結果を書くことを確かめる（docs/guides/testing.md「分岐の網羅率の警告」）
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "fileutils"

RSpec.describe "bin/check-branch-coverage" do
  let(:script) { File.expand_path("../../bin/check-branch-coverage", __dir__) }

  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  def write(path, text)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, text)
  end

  def git(*args)
    out, err, status = Open3.capture3("git", *args, chdir: @root)
    raise "git #{args.join(' ')}: #{err}" unless status.success?

    out
  end

  def commit_all(message)
    git("add", "-A")
    git("-c", "user.name=spec", "-c", "user.email=spec@example.com", "commit", "-q", "--allow-empty", "-m", message)
  end

  # 基準のブランチ main に base_files を、作業のブランチ work に head_files を置く
  def repository(base_files:, head_files:)
    git("init", "-q", "-b", "main")
    base_files.each { |path, text| write(path, text) }
    commit_all("base")
    git("checkout", "-q", "-b", "work")
    head_files.each { |path, text| write(path, text) }
    commit_all("head")
  end

  def arm(type, line, count) = { "type" => type, "start_line" => line, "start_column" => 2, "end_line" => line, "end_column" => 9, "count" => count }

  def write_coverage(results) = write("tmp/coverage.json", JSON.generate(results))

  def run_check(env: {})
    Open3.capture3({ "BASE_REF" => "main", "GITHUB_STEP_SUMMARY" => nil }.merge(env), script, chdir: @root)
  end

  let(:base_source) { "def a(x)\n  x ? 1 : 2\nend\n" }

  it "足した行にある未通過の分岐だけを一覧にし、行ごとに警告の注釈を出して、終了コード 0 で終わる" do
    repository(base_files: { "app/models/a.rb" => base_source },
      head_files: { "app/models/a.rb" => "#{base_source}def b(y)\n  y ? 3 : 4\nend\n" })
    write_coverage("app/models/a.rb" => [ arm("then", 2, 0), arm("else", 2, 0), arm("then", 5, 1), arm("else", 5, 0) ])

    out, err, status = run_check

    expect([ err, status.exitstatus ]).to eq([ "", 0 ])
    expect(out).to include("::warning file=app/models/a.rb,line=5::どの example も通らない分岐（else）")
    expect(out.scan("::warning").size).to eq(1)
  end

  it "変えた行の未通過の分岐も一覧にする" do
    repository(base_files: { "packs/sales/app/public/sales/c.rb" => base_source },
      head_files: { "packs/sales/app/public/sales/c.rb" => base_source.sub("x ? 1 : 2", "x ? 1 : 3") })
    write_coverage("packs/sales/app/public/sales/c.rb" => [ arm("then", 2, 0), arm("else", 2, 4) ])

    out, _err, status = run_check

    expect(status.exitstatus).to eq(0)
    expect(out).to include("::warning file=packs/sales/app/public/sales/c.rb,line=2::どの example も通らない分岐（then）")
    expect(out.scan("::warning").size).to eq(1)
  end

  it "差分にあって計測の結果に無いファイルを、計測なしとしてファイルごとに出す" do
    repository(base_files: { "app/models/a.rb" => base_source },
      head_files: { "lib/b.rb" => "def b = 1\n", "app/models/a.rb" => "#{base_source}# 足した行\n" })
    write_coverage("app/models/a.rb" => [ arm("then", 2, 0) ])

    out, _err, status = run_check

    expect(status.exitstatus).to eq(0)
    expect(out).to include("::warning file=lib/b.rb::計測なし（どの example も読み込まなかった）")
    expect(out).not_to include("file=app/models/a.rb")
  end

  it "計測の対象の外のファイル（bin/・config/）は、差分にあって未通過でも出さない" do
    repository(base_files: { "app/models/a.rb" => base_source },
      head_files: { "bin/tool.rb" => base_source, "config/initializers/x.rb" => base_source, "db/seeds.rb" => base_source })
    write_coverage("bin/tool.rb" => [ arm("then", 2, 0) ], "config/initializers/x.rb" => [ arm("then", 2, 0) ])

    out, _err, status = run_check

    expect(status.exitstatus).to eq(0)
    expect(out).not_to include("::warning")
  end

  it "基準の ref の、分岐点より後の変更を差分に数えない" do
    repository(base_files: { "app/models/a.rb" => base_source }, head_files: { "app/models/w.rb" => "def w = 1\n" })
    git("checkout", "-q", "main")
    write("app/models/a.rb", base_source.sub("x ? 1 : 2", "x ? 1 : 5"))
    commit_all("main moves on")
    git("checkout", "-q", "work")
    write_coverage("app/models/a.rb" => [ arm("then", 2, 0) ], "app/models/w.rb" => [])

    out, _err, status = run_check

    expect(status.exitstatus).to eq(0)
    expect(out).not_to include("app/models/a.rb")
  end

  it "まだ commit していない計測の対象のファイルは、すべての行を足した行として扱う" do
    repository(base_files: { "app/models/a.rb" => base_source }, head_files: {})
    write("app/models/new.rb", base_source)
    write_coverage("app/models/new.rb" => [ arm("then", 2, 0), arm("else", 2, 1) ])

    out, _err, status = run_check

    expect(status.exitstatus).to eq(0)
    expect(out).to include("::warning file=app/models/new.rb,line=2::どの example も通らない分岐（then）")
  end

  it "一覧をジョブの要約にも書く" do
    repository(base_files: { "app/models/a.rb" => base_source },
      head_files: { "app/models/a.rb" => "#{base_source}def b(y)\n  y ? 3 : 4\nend\n", "lib/b.rb" => "def b = 1\n" })
    write_coverage("app/models/a.rb" => [ arm("then", 5, 0) ])
    summary = File.join(@root, "summary.md")

    _out, _err, status = run_check(env: { "GITHUB_STEP_SUMMARY" => summary })

    expect(status.exitstatus).to eq(0)
    expect(File.read(summary)).to include("| `app/models/a.rb` | 5 | then |", "- `lib/b.rb`")
  end

  it "未通過の分岐も計測なしも無ければ、そのことを書いて終了コード 0 で終わる" do
    repository(base_files: { "app/models/a.rb" => base_source }, head_files: { "app/models/a.rb" => "#{base_source}# 足した行\n" })
    write_coverage("app/models/a.rb" => [ arm("then", 2, 0) ])

    out, _err, status = run_check

    expect(status.exitstatus).to eq(0)
    expect(out).to include("足した行と変えた行の分岐は、すべてどれかの example が通った")
    expect(out).not_to include("::warning")
  end

  it "計測の結果が無ければ失敗する" do
    repository(base_files: { "app/models/a.rb" => base_source }, head_files: {})

    _out, err, status = run_check

    expect(status.exitstatus).to eq(1)
    expect(err).to include("tmp/coverage.json")
  end

  it "計測の結果が読めなければ失敗する" do
    repository(base_files: { "app/models/a.rb" => base_source }, head_files: {})
    write("tmp/coverage.json", "{")

    _out, err, status = run_check

    expect(status.exitstatus).to eq(1)
    expect(err).to include("tmp/coverage.json")
  end

  it "基準の ref と HEAD の分岐点が見つからなければ失敗する" do
    repository(base_files: { "app/models/a.rb" => base_source }, head_files: {})
    write_coverage({})

    _out, err, status = run_check(env: { "BASE_REF" => "no-such-ref" })

    expect(status.exitstatus).to eq(1)
    expect(err).to include("no-such-ref")
  end

  # 全件を COVERAGE=1 で流している間は、同じプロセスで Coverage を始め直せないので、計測の部品は子のプロセスで流す
  describe "計測の結果を書く部分（spec/support/branch_coverage.rb）" do
    let(:recorder) { File.expand_path("../support/branch_coverage.rb", __dir__) }

    def record(program)
      Open3.capture3(RbConfig.ruby, "-e", <<~RUBY)
        require #{recorder.dump}
        BranchCoverage.start(root: #{@root.dump})
        #{program}
      RUBY
    end

    it "読み込んだ計測の対象のファイルの、未通過の分岐の座標と通過の回数を書き、対象の外のファイルを書かない" do
      write("lib/sample.rb", "module Sample\n  def self.call(flag)\n    if flag\n      :yes\n    else\n      :no\n    end\n  end\nend\n")
      write("config/settings.rb", "SETTING = ENV['X'] ? 1 : 2\n")

      _out, err, status = record(<<~RUBY)
        require #{File.join(@root, 'lib/sample.rb').dump}
        require #{File.join(@root, 'config/settings.rb').dump}
        Sample.call(true)
        BranchCoverage.write
      RUBY

      expect([ err, status.success? ]).to eq([ "", true ])
      results = JSON.parse(File.read(File.join(@root, "tmp/coverage.json")))
      expect(results.keys).to eq([ "lib/sample.rb" ])
      expect(results.fetch("lib/sample.rb")).to eq([
        { "type" => "then", "start_line" => 4, "start_column" => 6, "end_line" => 4, "end_column" => 10, "count" => 1 },
        { "type" => "else", "start_line" => 6, "start_column" => 6, "end_line" => 6, "end_column" => 9, "count" => 0 }
      ])
    end

    it "読み込んだが分岐の無いファイルは空の配列で書く" do
      write("app/models/plain.rb", "PLAIN = 1\n")

      _out, err, status = record("require #{File.join(@root, 'app/models/plain.rb').dump}\nBranchCoverage.write")

      expect([ err, status.success? ]).to eq([ "", true ])
      expect(JSON.parse(File.read(File.join(@root, "tmp/coverage.json")))).to eq("app/models/plain.rb" => [])
    end

    it "測り始めるときに前の実行の結果を消し、書く前に止まった実行の後に古い結果を残さない" do
      write("tmp/coverage.json", JSON.generate("app/models/old.rb" => []))

      _out, _err, status = record("exit 0")

      expect(status.success?).to be(true)
      expect(File.exist?(File.join(@root, "tmp/coverage.json"))).to be(false)
    end
  end
end
