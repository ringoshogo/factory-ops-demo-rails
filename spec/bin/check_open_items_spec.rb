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


  it "サイクル 10 からの実装レビューの証跡で、計画との違いの項目が judgment か decided の行の ID も「判断なし」も持たなければ落とす" do
    ledgers(open_items: "| OI-01 | judgment | 内容 | 出どころ | M16 | |\n| OI-02 | open | 内容 | 出どころ | M16 | |\n")
    evidence = <<~MD
      ## M16 テストの層

      #### 計画との違い

      - 作るもの 1 の引数を、計画の 2 つから 3 つにした
      - 作るもの 2 の置き場を決めた（OI-01）
      - 作るもの 3 は OI-02 の作業で、引数の形を決めた
      - 作るもの 4 の型を決めた。理由は長いので
        次の行に続ける（OI-01）
      - 作るもの 5 は計画の文のとおりに直した（判断なし）

      ##### 作るもの 6

      - 作るもの 6 の名前を決めた

      ```sh
      # 囲みの中の行は見出しでも項目でもない
      - 囲みの中の行
      ```

      - 囲みの後の項目も確かめる

      #### RED

      - 計画との違いの節の外の項目は確かめない
    MD
    write("docs/plans/cycle-11/implementation-reviews.md", evidence)
    write("docs/plans/cycle-09/implementation-reviews.md", evidence)

    _out, err, status = run_check
    expect(status).not_to be_success
    message = "計画との違いの項目に、judgment か decided の行の ID（OI-NN）も「判断なし」も無い\n"
    expect(err.lines).to eq([ 5, 7, 14, 21 ].map { |lineno| "docs/plans/cycle-11/implementation-reviews.md:#{lineno}: #{message}" })

    judged = evidence.gsub(/(3 つにした|引数の形を決めた|名前を決めた|項目も確かめる)$/, '\1（判断なし）')
    write("docs/plans/cycle-11/implementation-reviews.md", judged)
    _out, err, status = run_check
    expect(err).to eq("")
    expect(status).to be_success
  end

  it "サイクル 10 からの計画レビューの証跡が、dev-cycle.md「1. 計画レビュー」の観点の名前を欠けば落とす" do
    ledgers(open_items: "")
    write("docs/guides/dev-cycle.md", <<~MD)
      ## 1. 計画レビュー

      1. **設計文書との整合**：説明
      2. **順序と依存**：説明

      ## 2. マイルストーンの実装

      1. **計画への準拠と範囲**：説明
    MD
    write("docs/plans/cycle-10/plan-review.md", "| 観点 | 判定 |\n|---|---|\n| 設計文書との整合 | 指摘なし |\n")
    write("docs/plans/cycle-09/plan-review.md", "観点の名前を書かない\n")

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err.lines).to eq([ "docs/plans/cycle-10/plan-review.md: 計画レビューの観点「順序と依存」の結果が無い\n" ])

    write("docs/plans/cycle-10/plan-review.md", "| 設計文書との整合 | 指摘なし |\n| 順序と依存 | 指摘あり |\n")
    _out, err, status = run_check
    expect(err).to eq("")
    expect(status).to be_success
  end

  it "本物の dev-cycle.md の計画レビューの観点を、規則の文が言う数だけ集め、1 つずつ欠いた証跡を落とす" do
    rule = File.read(File.expand_path("../../docs/guides/dev-cycle.md", __dir__))
    count = rule[/^## 1\. 計画レビュー\n.*?観点は次の (\d+) つである/m, 1].to_i
    expect(count).to be_positive
    ledgers(open_items: "")
    write("docs/guides/dev-cycle.md", rule)
    write("docs/plans/cycle-10/plan-review.md", "観点の名前を書かない\n")

    _out, err, status = run_check
    expect(status).not_to be_success
    # 本物の規則の文書は、この台帳に無い ID も引くので、計画レビューの証跡の行だけを読む
    aspects = err.lines.filter_map { |line| line[/plan-review\.md: 計画レビューの観点「(.+)」の結果が無い/, 1] }
    expect(aspects.size).to eq(count)

    aspects.each do |missing|
      write("docs/plans/cycle-10/plan-review.md", (aspects - [ missing ]).join("\n"))
      _out, err, status = run_check
      expect(status).not_to be_success
      expect(err.lines.grep(/plan-review\.md/)).to eq([ "docs/plans/cycle-10/plan-review.md: 計画レビューの観点「#{missing}」の結果が無い\n" ])
    end
  end

  it "計画レビューの証跡があるのに、dev-cycle.md から観点の名前を読めなければ落とす" do
    ledgers(open_items: "")
    write("docs/plans/cycle-10/plan-review.md", "観点の名前を書かない\n")

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err.lines).to eq([ "docs/guides/dev-cycle.md: 「1. 計画レビュー」から観点の名前を読めない\n" ])

    write("docs/guides/dev-cycle.md", "## 1. 計画レビュー\n\n観点を太字で並べない\n\n## 2. マイルストーンの実装\n")
    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err.lines).to eq([ "docs/guides/dev-cycle.md: 「1. 計画レビュー」から観点の名前を読めない\n" ])
  end

  it "サイクル 11 からの実装レビューの証跡で、マイルストーンの節が計画の完了条件の git grep を件数とともに持たなければ落とす" do
    ledgers(open_items: "")
    write("docs/implementation-plan.md", <<~MD)
      # 実装計画

      ## M16 テストの層と重要シナリオ

      ```sh
      git grep -n -e before -- docs   # 0 件
      bundle exec rspec spec/a_spec.rb
      ```

      **残り（サイクル 11）**：残りを作る。

      ```sh
      git grep -n -e rest -- packs   # 1 件
      ```

      ## M17 N+1 の検出

      ```sh
      bundle exec rspec spec/b_spec.rb
      ```
    MD
    evidence = <<~MD
      ## M16 テストの層と重要シナリオ

      本文の git grep -n -e before -- docs は囲みの外なので数えない

      ```sh
      bundle exec rspec spec/a_spec.rb
      ```

      ## M16 の残り（サイクル 11）：残り

      ```sh
      git grep -n -e rest -- packs
      ```

      ## M17 N+1 の検出

      ```sh
      bundle exec rspec spec/b_spec.rb
      ```
    MD
    write("docs/plans/cycle-11/implementation-reviews.md", evidence)
    write("docs/plans/cycle-10/implementation-reviews.md", evidence)

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err.lines).to eq([
      "docs/plans/cycle-11/implementation-reviews.md:1: M16 の節に、完了条件の「git grep -n -e before -- docs」を流した件数が無い\n",
      "docs/plans/cycle-11/implementation-reviews.md:9: M16 の残り（サイクル 11）の節に、完了条件の「git grep -n -e rest -- packs」を流した件数が無い\n"
    ])

    counted = evidence.sub("```sh\nbundle exec rspec spec/a_spec.rb", "```sh\ngit grep -n -e before -- docs   # 0 件\nbundle exec rspec spec/a_spec.rb")
                      .sub("git grep -n -e rest -- packs\n", "git grep -n -e rest -- packs   # 1 件（packs/x.rb:1）\n")
    write("docs/plans/cycle-11/implementation-reviews.md", counted)
    _out, err, status = run_check
    expect(err).to eq("")
    expect(status).to be_success
  end

  it "本物の計画とサイクル 10 の実装レビューの証跡は、完了条件の git grep の件数を持ち、1 行の件数を消すと落ちる" do
    plan_text = File.read(File.expand_path("../../docs/implementation-plan.md", __dir__))
    evidence = File.read(File.expand_path("../../docs/plans/cycle-10/implementation-reviews.md", __dir__))
    ledgers(open_items: "")
    write("docs/implementation-plan.md", plan_text)
    write("docs/plans/cycle-11/implementation-reviews.md", evidence)

    # 本物の証跡は、この台帳に無い ID も引くので、件数の行だけを読む
    _out, err, = run_check
    expect(err.lines.grep(/を流した件数が無い/)).to eq([])

    line = evidence.lines.find { _1.start_with?("git grep -n 'ignored_columns' -- packs") }
    write("docs/plans/cycle-11/implementation-reviews.md", evidence.sub(line, line.sub(/\s+#.*/, "")))
    _out, err, = run_check
    expect(err.lines.grep(/を流した件数が無い/)).to eq([
      "docs/plans/cycle-11/implementation-reviews.md:138: M54 の残り（サイクル 10）の節に、完了条件の「git grep -n 'ignored_columns' -- packs」を流した件数が無い\n"
    ])
  end

  it "サイクル 12 からの実装レビューの証跡で、完了条件の git grep の件数の注釈が流した版の commit を持たなければ落とす" do
    ledgers(open_items: "")
    write("docs/implementation-plan.md", <<~MD)
      # 実装計画

      ## M16 テストの層と重要シナリオ

      ```sh
      git grep -n -e before -- docs   # 0 件
      ```
    MD
    evidence = <<~MD
      ## M16 テストの層と重要シナリオ

      ```sh
      git grep -n -e before -- docs   # 0 件
      ```
    MD
    # サイクル 11 の証跡は、件数だけで通る
    write("docs/plans/cycle-11/implementation-reviews.md", evidence)
    write("docs/plans/cycle-12/implementation-reviews.md", evidence)

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err.lines).to eq([
      "docs/plans/cycle-12/implementation-reviews.md:1: M16 の節に、完了条件の「git grep -n -e before -- docs」を流した版の commit が無い\n"
    ])

    # ` で囲まない SHA は bin/check-commit-refs が確かめないので、版として数えない。7 桁に満たない語も数えない
    [ "# 0 件（abc1234。この後の commit は証跡だけを変える）", "# 0 件（`abc12`）" ].each do |note|
      write("docs/plans/cycle-12/implementation-reviews.md", evidence.sub("# 0 件", note))
      _out, err, = run_check
      expect(err.lines.grep(/版の commit が無い/).size).to eq(1)
    end

    write("docs/plans/cycle-12/implementation-reviews.md", evidence.sub("# 0 件", "# 0 件（`abc1234`。この後の commit は証跡だけを変える）"))
    _out, err, status = run_check
    expect(err).to eq("")
    expect(status).to be_success
  end

  it "本物の計画とサイクル 11 の実装レビューの証跡は、版を ` で囲めば通り、1 行の版を消すと落ちる" do
    plan_text = File.read(File.expand_path("../../docs/implementation-plan.md", __dir__))
    # サイクル 11 の証跡は版を ` で囲まずに書いたので、囲んだ形に写して照らす
    evidence = File.read(File.expand_path("../../docs/plans/cycle-11/implementation-reviews.md", __dir__)).gsub("（934267a。", "（`934267a`。")
    ledgers(open_items: "")
    write("docs/implementation-plan.md", plan_text)
    write("docs/plans/cycle-12/implementation-reviews.md", evidence)

    # 本物の証跡は、この台帳に無い ID も引くので、件数と版の行だけを読む
    _out, err, = run_check
    expect(err.lines.grep(/を流した(件数|版の commit )が無い/)).to eq([])

    line = evidence.lines.find { _1.start_with?("git grep -n 'ignored_columns' -- packs") }
    write("docs/plans/cycle-12/implementation-reviews.md", evidence.sub(line, line.sub(/（.*）/, "")))
    _out, err, = run_check
    expect(err.lines.grep(/を流した(件数|版の commit )が無い/)).to eq([
      "docs/plans/cycle-12/implementation-reviews.md:7: M58 の節に、完了条件の「git grep -n 'ignored_columns' -- packs」を流した版の commit が無い\n"
    ])
  end

  it "件数を数字で書かない注釈を数えず、囲みの中の見出しで節を区切らず、~~~ の囲みも読み、番号の無い「残り」の見出しを落とす" do
    ledgers(open_items: "")
    write("docs/implementation-plan.md", <<~MD)
      # 実装計画

      ## M16 テストの層と重要シナリオ

      ```sh
      git grep -n -e before -- docs   # 0 件
      ```
    MD
    evidence = <<~MD
      ## M16 テストの層と重要シナリオ

      ```markdown
      ## M17 見出しの見本は節を区切らない
      ```

      ~~~sh
      git grep -n -e before -- docs   # 件数は最後の版で書く
      ~~~

      ## M16 の残り：番号の無い見出し
    MD
    write("docs/plans/cycle-11/implementation-reviews.md", evidence)

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err.lines).to eq([
      "docs/plans/cycle-11/implementation-reviews.md:1: M16 の節に、完了条件の「git grep -n -e before -- docs」を流した件数が無い\n",
      "docs/plans/cycle-11/implementation-reviews.md:11: 「残り」の節の見出しが「M16 の残り（サイクル NN）」の形でない\n"
    ])

    fixed = evidence.sub("# 件数は最後の版で書く", "# 0 件").sub("M16 の残り：", "M16 の残り（サイクル 11）：")
    write("docs/plans/cycle-11/implementation-reviews.md", fixed)
    _out, err, status = run_check
    expect(err).to eq("")
    expect(status).to be_success
  end
end
