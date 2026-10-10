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
