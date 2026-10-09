# 残件と改善の候補の台帳を、bin/check-open-items が機械で守ることを確かめる（docs/guides/dev-cycle.md「機械で守ること」）
require "open3"
require "tmpdir"
require "fileutils"

RSpec.describe "bin/check-open-items" do
  let(:script) { File.expand_path("../../bin/check-open-items", __dir__) }

  let(:plan) do
    <<~MD
      # 実装計画

      ## M16 テストの層と重要シナリオ

      ## M17 N+1 の検出
    MD
  end

  let(:header) do
    <<~MD
      | ID | 状態 | 内容 | 出どころ | 引当先 | 結果 |
      |---|---|---|---|---|---|
    MD
  end

  let(:backlog_header) do
    <<~MD
      | ID | 状態 | テーマ | なぜ今か（シグナルの出どころ） | 追加日 | 判定の記録 |
      |---|---|---|---|---|---|
    MD
  end

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

  def run_check(*args, stdin: "")
    system("git", "-C", @root, "init", "-q", exception: true)
    system("git", "-C", @root, "add", "-A", exception: true)
    Open3.capture3(script, "--root", @root, *args, stdin_data: stdin)
  end

  def ledgers(open_items:, backlog: "")
    write("docs/implementation-plan.md", plan)
    write("docs/plans/open-items.md", header + open_items)
    write("docs/plans/improvement-backlog.md", backlog_header + backlog)
  end

  it "形の正しい台帳と、台帳にある ID の参照を通す" do
    ledgers(
      open_items: "| OI-01 | open | 内容 | 出どころ | M16 | |\n| OI-02 | closed | 内容 | 出どころ | M16 | abc1234 |\n",
      backlog: "| IB-01 | 見送り | テーマ | シグナル | 2026-10-10 | いまは要らない |\n"
    )
    write("docs/handoff.md", "OI-01 と IB-01 を見る\n")

    _out, err, status = run_check
    expect(err).to eq("")
    expect(status).to be_success
  end

  it "台帳に無い ID の参照を落とす" do
    ledgers(open_items: "| OI-01 | open | 内容 | 出どころ | M16 | |\n")
    write("docs/handoff.md", "OI-02 を見る\n")

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err).to include("docs/handoff.md:1: OI-02 が台帳に無い")
  end

  it "引当先に条件を書いた行を落とす" do
    ledgers(open_items: "| OI-01 | open | 内容 | 出どころ | 公開するとき | |\n")

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err).to include("マイルストーンの番号（M16 など）ではない")
  end

  it "計画に節が無いマイルストーンを引当先にした行を落とす" do
    ledgers(open_items: "| OI-01 | open | 内容 | 出どころ | M99 | |\n")

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err).to include("引当先 M99 が docs/implementation-plan.md の節に無い")
  end

  it "SHA の無い closed と、理由の無い decided を落とす" do
    ledgers(open_items: "| OI-01 | closed | 内容 | 出どころ | M16 | 直した |\n| OI-02 | decided | 内容 | 出どころ | M16 | |\n")

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err).to include("OI-01 は closed なのに、結果に commit の SHA が無い")
    expect(err).to include("OI-02 は decided なのに、結果に閉じた理由が無い")
  end

  it "番号の飛びと重複を落とす" do
    ledgers(open_items: "| OI-01 | open | 内容 | 出どころ | M16 | |\n| OI-01 | open | 内容 | 出どころ | M16 | |\n")

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err).to include("ID が OI-01 だが、前の行から続く番号は OI-02")
  end

  it "なぜ今かの無い改善の候補と、理由の無い見送りを落とす" do
    ledgers(open_items: "", backlog: "| IB-01 | 見送り | テーマ |  | 2026-10-10 | |\n")

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err).to include("IB-01 のなぜ今か（シグナルの出どころ）が空")
    expect(err).to include("IB-01 は 見送り なのに、判定の記録が空")
  end

  it "--due は、引当先がそのマイルストーンの open と blocked-user だけを落とす" do
    ledgers(open_items: <<~ROWS)
      | OI-01 | open | 内容 | 出どころ | M16 | |
      | OI-02 | blocked-user | 内容 | 出どころ | M16 | |
      | OI-03 | judgment | 内容 | 出どころ | M16 | |
      | OI-04 | open | 内容 | 出どころ | M17 | |
    ROWS

    _out, err, status = run_check("--due", "M16")
    expect(status).not_to be_success
    expect(err.lines.size).to eq(2)
    expect(err).to include("OI-01 が open").and include("OI-02 が blocked-user")

    _out, _err, status = run_check("--due", "M17")
    expect(status).not_to be_success

    ledgers(open_items: "| OI-01 | closed | 内容 | 出どころ | M16 | abc1234 |\n")
    _out, err, status = run_check("--due", "M16")
    expect(err).to eq("")
    expect(status).to be_success
  end

  it "--text - は、標準入力（PR の本文）の参照も確かめる" do
    ledgers(open_items: "| OI-01 | open | 内容 | 出どころ | M16 | |\n")

    _out, err, status = run_check("--text", "-", stdin: "OI-01 を閉じた。OI-07 も見た\n")
    expect(status).not_to be_success
    expect(err).to include("(標準入力):1: OI-07 が台帳に無い")
  end
end
