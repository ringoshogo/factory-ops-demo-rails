# サイクル 2 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M34 依存の更新と使っていない部品の削除

PR #33（`m34-deps`、base は `cycle-02-plan`）。どちらの系統も Go で、Critical と High は無かった。Medium と Low は同じブランチの commit で直し、違和感は改善の候補に移した。High 以上が無いので、読み直しには出していない。

| 系統 | 判定 |
|---|---|
| Codex | Go |
| Claude | Go |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘なし |
| 正しさ | 指摘なし | 指摘（C1） |
| 境界と規約 | 指摘なし | 指摘（C2） |
| テストの検出力 | 指摘（X1） | 指摘なし |
| 参照の維持 | 指摘（X2・X3） | 指摘（C3） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | X1：`spec/platform/framework_loading_spec.rb` の、部品を外す前の RED の記録を確かめられない | Codex は PR の本文を取得できなかった。RED の記録は PR の本文と、下の「実装の記録」にある | この commit |
| Low | Codex | X2：計画の作るもの 1 の「いまの spec は拒否の一覧で」が、許した一覧の spec を足した後の状態と合わない | 拒否の一覧の example を指す書き方に直した | `d3a5446` |
| Low | Codex | X3：`Gemfile` に Action Cable 用の Redis の説明とコメントアウトの gem が残る | 2 行を消した。同じ種類を `git grep -i` で「Action Cable」「Active Storage」「storage」で探し、C3 の残りを見つけた | `d3a5446` |
| Low | Claude | C1：本番の環境を見る example が、親の `RAILS_LOG_LEVEL` を子のプロセスに引き継ぎ、`RAILS_LOG_LEVEL=debug` で流すと落ちる | 子の環境で `RAILS_LOG_LEVEL` を外した。`RAILS_LOG_LEVEL=debug` で流して通り、外さない形に戻すと落ちることを確かめた | `d3a5446` |
| Low | Claude | C2：X3 と同じ。完了条件の `git grep` は小文字の `action_cable` だけを探すので拾わない | X3 と同じ | `d3a5446` |
| Low | Claude | C3：Active Storage の保存先（`storage/.keep`・`tmp/storage/.keep`）と、`.gitignore`・`.dockerignore` の除外の行が残る | ディレクトリと除外の行を消し、`guides/config.md`「使っていない機能の設定」の表に足した | `d3a5446`・この commit |

違和感は次のように扱った。

- Codex：依存の向きの表の重複行で失敗する分岐に example が無い → example を足し、失敗させる行を消すと落ちることを確かめた（`d3a5446`）
- Claude 1：`Gemfile.lock` の `BUNDLED WITH` が 2.5.3 のままで、net-pop の依存が落ちることがまた起きうる → IB-18
- Claude 2：ADR 008「確認した事項」が、比べた結果を地の文と引用ブロックの両方に書いている → 引用ブロックの 1 つに寄せた（`d3a5446`）
- Claude 3：拒否の一覧を見る既存の 2 つの example が、許した一覧の example と重複して見える → テストの環境も同じ経路を止めていることを見る役だと、コメントで 1 文示した（`d3a5446`）

### 実装の記録

テストを先に書き、実装の前に流した。壊したファイルは複製から戻した。

| 対象 | RED の落ち方・壊して落ちること |
|---|---|
| `spec/platform/framework_loading_spec.rb` | 部品を外す前（`f39ca95` の上）に流し、`got: ["ActiveStorage::Engine", "ActionMailbox::Engine", "ActionText::Engine", "ActionCable::Engine"]` で 2 examples, 1 failure。外した後に `require "action_cable/engine"` を戻すと `got: ["ActionCable::Engine"]` で落ち、`require "action_mailer/railtie"` を消すと起動で落ちる |
| `spec/packwerk/dependency_table_spec.rb` | 表は計画レビューでいまの `package.yml` に合わせたので、書いた時点で通る（計画のとおり）。表の `billing` の行から `contracts` を消すと落ち、`packs/inventory/package.yml` に `packs/contracts` を足すと落ちる（OI-58） |
| `spec/platform/logging_spec.rb` の許した一覧 | `ActionMailer::LogSubscriber` の購読を外さないと落ち、`ActionDispatch::DebugExceptions` をミドルウェアから消さないと落ちる |

止めたログの経路の調べ直し（IB-14）は、許した一覧の spec を依存を上げる前に入れ（`f39ca95`）、上げた後も通ることで確かめた。比べた結果と判断は ADR 008 と `guides/config.md`「止めたフレームワークの文字列のログ」にある。

`bundle update` を bundler 2.5.3 で流すと、net-pop の net-protocol への依存が lockfile から落ち、`docker build` の `bundle install`（`BUNDLE_DEPLOYMENT`）が失敗した。`bundle update net-pop` で戻し（`f9d11ac`）、`docker build` が通ることと、イメージの中で Ruby 3.4.11 で起動して `ActiveStorage::Engine` が無く `ActionMailer::Base` があることを確かめた。

### 確かめたこと

警告の件数は、リポジトリのコード（spec を除く）から出たものを数えた。

```sh
RUBYOPT=-W:deprecated bundle exec rspec 2> tmp/deprecated.log    # 終了コード 0
grep -cE "^$PWD/(app|packs|lib|config|bin)/[^:]+:[0-9]+: warning:" tmp/deprecated.log
```

| 対象 | Ruby | リポジトリのコードの警告 | 全体の `warning:` の行 |
|---|---|---|---|
| `b2e8f2a`（上げる前） | 3.3.3 | 0 | 0 |
| `e0035e9`（上げた後） | 3.4.11 | 0 | 3（gem の parser 3.3.12.0 の chilled string） |

指摘を直した後の `d3a5446` で、Ruby 3.4.11 で共通の完了条件と M34 の完了条件を流した。

```sh
bundle exec rspec spec/platform/framework_loading_spec.rb spec/packwerk/dependency_table_spec.rb   # 0 failures
bundle exec rspec --format progress --format json --out tmp/rspec.json   # 1130 examples, 0 failures
git grep -nE "active_storage|action_mailbox|action_text|action_cable|image_processing|kamal" -- config app Gemfile Dockerfile   # 終了コード 1
test "$(ruby -e 'print RUBY_VERSION')" = "$(cat .ruby-version)"   # 終了コード 0
bin/bundler-audit                              # No vulnerabilities found
bin/rubocop                                    # no offenses
bin/packwerk validate && bin/packwerk check    # 違反なし
bin/check-structure                            # 終了コード 0
bin/rails graphql:schema:idl && git diff --exit-code schema.graphql   # 差分なし
BASE_REF=origin/cycle-02-plan bin/check-schema-compat   # 落とす変更は無い
bin/check-open-items --due M34                 # 終了コード 0
bin/check-commit-refs                          # 終了コード 0
```

PR #33 の CI（lint・scan_ruby・test）は、Ruby 3.4.11 で通った。

### 層ごとの表

`d3a5446` で流した全件の出力を `bin/test-layers` に渡した結果。未分類のファイルは無く、目安を外れた層は無い。

| 層 | example | 割合 | 目安 |
|---|---|---|---|
| 単体 | 121 | 43.4% | — |
| 結合 | 118 | 42.3% | — |
| シナリオ | 40 | 14.3% | 50% 以下 |
| ガード | 851 | — | 数えない |

### 残件の処理

| ID | 処理 |
|---|---|
| OI-58 | 作者の判断で `decided` 済み。表と `package.yml` の一致を確かめる spec を足した（`e89cf83`） |
| OI-59 | M34 は CI のワークフローを変えていない（setup-ruby が `.ruby-version` を読む）ので、判断の前提は変わらない。`judgment` のまま、サイクル末の作者の確認に回す |

## M35 分岐の網羅率の警告

PR #34（`m35-branch-coverage`、base は `m34-deps`）。どちらの系統も Go で、Critical と High は無かった。Medium と Low は同じブランチの commit で直し、違和感は改善の候補に移した。High 以上が無いので、読み直しには出していない。

| 系統 | 判定 |
|---|---|
| Codex | Go |
| Claude | Go |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘（C1） |
| 正しさ | 指摘（X1） | 指摘（C2・C3） |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（X2） | 指摘（C4） |
| 参照の維持 | 指摘（X3） | 指摘（C5） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | X1：`bin/check-branch-coverage` がパッチの見出しからファイルの名前を読むので、引用された名前（引用符・改行を含む）を読み違え、ハンクを直前のファイルに付ける。追跡していないファイルの名前も引用のまま開く | 名前を `-z` の NUL 区切りで取り、パッチをファイルごとに `:(literal)` のパスで取る形にした。引用符を含む名前のファイルを、追跡しているものと追跡していないものの両方で照らす example を足した。直す前の形で落ちることを確かめた | `81cacea` |
| Low | Codex | X2：計測の部品の 3 つの example に RED が無い | 部品を spec より先に書いたことを下の「実装の記録」に書いた。検出力は、壊して落ちることで確かめた | この commit |
| Low | Codex | X3：`guides/bin.md` の「計測の結果が無いか読めないときだけ失敗する」が、基準の ref との差分を取れないときの失敗と合わない | `guides/bin.md` とスクリプトの冒頭のコメントに、差分を取れないときも失敗すると書いた | `81cacea` |
| Low | Claude | C1：CI の test のジョブの要約に、向き先からの差分の一覧が出ることを確かめていない | PR #34 の CI（run 38071309023）の test のジョブで、`BASE_REF: origin/m34-deps` と「基準: origin/m34-deps との分岐点 9e99274」が出たことを確かめた | この commit |
| Medium | Claude | C2：照合が腕の始まる行だけを見るので、複数行の `if` の条件の行だけを変えた変更と、既存の腕の中に足した行を拾わない | 計測の結果に条件の始まる行（`condition_line`）と、座標が条件の式全体と同じ腕か（`implicit`）を持たせ、条件の行と腕の範囲の行を差分に当てる形にした。`else` の無い `if` の書いていない側は条件の行だけに当てる。条件の行だけを変える example、腕の中に行を足す example、`implicit` を書く example を足し、直す前の形で落ちることを確かめた。`when` の条件だけの変更は Coverage が座標を返さないので拾わず、`guides/testing.md` に書いて IB-21 に積んだ | `81cacea`・この commit |
| Medium | Claude | C3：`packs/*/lib/**/*.rb` が計測の対象から抜け、`packs/platform/lib/` の分岐を変えても警告も計測なしも出ない | `config/branch_coverage.yml` に足し、計画の「計測の範囲」と `guides/testing.md` を合わせた。パッケージの lib/ のファイルを照らす example を足した | `81cacea` |
| Low | Claude | C4：名前の変更を照らす example が無い | 基準のファイルを `git mv` し、移した先の変えていない行の未通過が出る example を足した。パッチをファイルごとにパスで取るので、名前の変更の検出を入れても移した先は全行を足した行になり、`--no-renames` を外してもこの example は落ちない | `81cacea` |
| Low | Claude | C5：`guides/testing.md` の照合の説明が、条件の行だけの変更の漏れを書いていない | C2 の照合の規則に合わせて段落を書き直し、行を消しただけの変更と `when` の条件だけの変更を拾わないことを書いた | `81cacea`・この commit |

違和感は次のように扱った。

- Codex：CI の配線を spec で守らない判断（OI-59）が、test のジョブの分岐の網羅率のステップにも広がる → OI-59 の判断と同じ扱いにし、OI-59 のサイクル末の作者の確認に含める
- Claude 1：パッチの見出しの `+++ b/` の読み取りが、足した行の内容や末尾にタブの付くパスで読み違える → X1 の直しで見出しを読まなくなった（`81cacea`）
- Claude 2：追跡していないファイルを、対象で絞る前にすべて読む → X1 の直しで、対象で絞ってから読むようにした（`81cacea`）
- Claude 3：行を消しただけの変更は警告に出ない → C5 で `guides/testing.md` に書いた
- Claude 4：main への force push で `github.event.before` が履歴に無いと、test のジョブも落ちる → IB-20
- Claude 5：IB-01 の状態が「起票済み」のまま → 効いたかはサイクル 02 の振り返りで警告の件数で判定するので、状態はそのときに進める

### 実装の記録

照合の spec は、スクリプトを書く前に流し、14 examples, 11 failures（`Errno::ENOENT`）で落ちた。計測の部品（`spec/support/branch_coverage.rb`）は spec より先に書いたので、RED の記録は無い。壊したファイルは複製から戻した。

| 対象 | 壊して落ちること |
|---|---|
| `bin/check-branch-coverage` | 差分の行との照合を外す・通過の回数の判定を外す・対象の絞り込みを外す・計測なしを飛ばす・追跡していないファイルを足さない・分岐点の代わりに基準の先端と比べる・ハンクの行数の省略を 0 と読む・`implicit` の扱いを外す・条件の行を当てない、のそれぞれで落ちる |
| `spec/support/branch_coverage.rb` | 対象の絞り込みを外すと、測り始めるときに前の結果を消す処理を外すと、それぞれ落ちる |
| 失敗の経路の 7 つの example | `NOT_FOUND` の `path` を変える、`cancelled_at || shipped_at` の片側を外す、受け手の `else raise` を外す、のそれぞれで、足した example が落ちる |

失敗の経路の 8 か所の通過の回数は、PR #34 の本文の表にある。出荷指示の `cancel` の `NOT_FOUND` は、足す前から既存の example が通していた（通過の回数 1）ので、重ねて足していない。

### 確かめたこと

`81cacea` で、Ruby 3.4.11 で共通の完了条件と M35 の完了条件を流した。

```sh
bundle exec rspec spec/bin/check_branch_coverage_spec.rb    # 20 examples, 0 failures
COVERAGE=1 bundle exec rspec --format progress --format json --out tmp/rspec.json   # 1158 examples, 0 failures
BASE_REF=origin/main bin/check-branch-coverage              # 終了コード 0、一覧は空
bin/rubocop                                    # no offenses
bin/packwerk validate && bin/packwerk check    # 違反なし
bin/check-open-items --due M35                 # 終了コード 0
bin/check-commit-refs                          # 終了コード 0
bin/test-layers tmp/rspec.json                 # 未分類なし
```

警告の件数は 0 件で、example を足した件数も 0 件である。M35 の差分は計測の対象のファイルを変えていない。全体では、198 ファイル・382 の分岐の腕のうち 32 が未通過である（`81cacea` の全件の計測）。

CI の test のジョブの時間は、PR #33 の 7 分 26 秒から、PR #34 の最初の push で 9 分 54 秒になった。

### 残件の処理

引当先が M35 の残件は無い。
