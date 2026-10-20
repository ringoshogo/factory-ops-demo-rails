# サイクル 11 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M58 spec を乱順で流し、移行の spec の後始末で消した列の読み込みを戻す

`m58-random-order`（base は `main`）。サイクル 11 の計画のブランチ `cycle-11-plan` の先端 `7e7b88a` から切った。計画の PR（#108）は着手の後に main に入ったので、M58 の差分は `7e7b88a..` で、PR の差分もそれだけである。

PR #109 の実装レビューは、実装者が 2 系統に同じ依頼で出した。どちらの系統も、`7e7b88a..98a94b0` の diff を `git show 98a94b0:<パス>` か同じ木の作業ツリーで読んだ。2 系統とも Go で、High 以上は無く、読み直しには出していない。

- Claude：手元で完了条件の `git grep` 3 本（0・0・0 件）と、全件を `--seed` 1・2・3 で流した（3 つとも 3200 examples, 0 failures）。壊して落ちる記録の 1〜3 を複製から追試して同じ落ち方を確かめ、後始末の `DROP COLUMN IF EXISTS` を `DROP COLUMN` にする壊し方を足した（後始末を確かめる example が 2 回目の後始末の `PG::UndefinedColumn` で落ちた）。`.rspec-local` に `--order defined` を一時に置き、親を `SPEC_OPTS="--order defined"` で流しても子に漏れないことを確かめた。`items` を表に持つモデルが `Sales::Item` だけであることを、読み込んだ 55 のモデルから数えた
- Codex：読み取り専用で流した。DB を使う spec は流さず、完了条件の `git grep` 3 本（0・0・0 件）と、commit の流す対象をメモリの上に読んだ seed 1 の dry-run（並びは `8,3,6,4,10,9,2,7,1,5`）を流し、rspec-core 3.13.6 と activerecord 8.1.4 の原文を読んだ

Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。

| 系統 | 判定 |
|---|---|
| Codex | Go（Medium 1・Low 1） |
| Claude | Go（Low 3） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘（R1・R2） |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘（R3） |
| テストの検出力 | 指摘（R2） | 指摘なし |
| 参照の維持 | 指摘（R1） | 指摘（R3） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex R1 | `implementation-plan.md` の M54 の残りの節（IB-151 の段落）に、前の規則 3 の「足し直すあいだは外さず」、`unit_price` を「残す」、列を読ませてから消す example の作り方が残り、M58 で替えたことが書かれていない | 3 か所に、M58 で替えたことを括弧で書き足した（規則 3 は後始末の形に替えた、`unit_price` は外した、example は後始末を確かめる形に替えた）。M54 の残りの節は当時の計画なので、文は書き換えていない。前の形を `git grep -n -e '外さず' -e '残す。移行の spec' -- docs/implementation-plan.md` で数え、M54 の残りの節の 2 行（どちらも書き足した行）と M58 の節のほかは、行列テストのポリシーを外す別の文の 1 行（`:1366`）だけであることを確かめた | この節を載せた commit |
| Low | Codex R2 | 定義の順と違う並びを確かめる example に、RED も壊して落ちる記録も無い | 流す対象のグループに `order: :defined` を付けて seed が並びを変えなくなる壊し方を足し、この example だけが落ちることを確かめた（下の壊して落ちる記録の表） | 同上 |
| Low | Claude R1 | 完了条件の `git grep` 3 本に、流した commit が書いていない | 3 本を最後の commit と同じ木で流し直し、行の注釈に書いた | 同上 |
| Low | Claude R2 | `bin/ci` の rspec の seed 59808 が、どの版のものか読み取れない | 段落に `5bb8dc7` の `bin/ci` だと書いた | 同上 |
| Low | Claude R3 | `spec/spec_helper.rb` のコメントが、コマンドラインの `--seed`・`--order` が優先する根拠として `guides/testing.md`「層への配分」を指すが、その節に優先のことは無い。`spec_order_spec.rb` の冒頭も原文のファイルを指さない | どちらも、rspec-core 3.13.6 の `configuration_options.rb` の `force?` と `ordering.rb` の `ConfigurationManager#force` を指す形にした | 同上 |

違和感は次のように扱った。

- Claude 1：子は `.rspec` の `--require packs/rails/rspec` も読むので、計画と流す対象の「`--require spec_helper` だけで足り」は前提を書き落としている → 改善の候補 IB-160 に移した
- Claude 2：書き直した example は後始末を example の中で呼び、`after` がもう一度呼ぶので、2 回呼んでも同じ形に戻ることの守りを兼ねるが、それがどこにも書いていない → example のコメントに書いた
- Claude 3：規則 3 を守るのが移行の spec の 1 つの example だけである → 既にある IB-158 で扱う。移していない
- Codex：なし

分岐の網羅率の警告は、基準 `7e7b88a` で 0 件で、example を足したものは無い。

### 実装の記録

下の spec の行の番号は、実装レビューの直しの後の版のものである（直しで `spec_order_spec.rb` の冒頭のコメントが 1 行増え、レビューに出した版の `:30`・`:43` が `:31`・`:44` になった）。

#### 計画との違い

- 着手の時点の全件は、計画の見込みどおり乱順で落ちなかった。`7e7b88a` で `TEST_DATABASE=factory_ops_m58_test bundle exec rspec --seed <seed>` を seed 4・5・6 で流し、どれも 3198 examples, 0 failures で、1 回に約 3 分 22〜26 秒かかった。直した spec は無く、計画の「判断」の裏返る条件にも当たらない（判断なし）
- 計画が「実装で決める」とした後始末のメソッドの名前を `restore_current_schema` にし、`describe` のブロックの局所変数（受注明細の CHECK 制約のいまの定義）を読むので `define_method` で定義した（OI-242 の (1)）
- 乱順が既定であることを確かめる (a)〜(c) を 1 つの example に置き、定義の順と違う並びを確かめる example を別に置いた。後者は、`--order defined` で流した並びが定義の順であることを対照に確かめてから、seed 1 の並びがそれと違うことを確かめる。seed 1 は 10 個を `8,3,6,4,10,9,2,7,1,5` に並べる（OI-242 の (2)）
- (c) の値は、子に渡す環境変数 `SPEC_ORDER_RAND_FILE` が指すファイルに、流す対象の 1 つ目の example が書く。親の spec は `spec/platform` のほかの spec と同じく `rails_helper` を読む（OI-242 の (3)・(4)）
- `guides/testing.md`「層への配分」の 1 文は、example をテナントで包む `around` の段落の前に、独立した段落で置いた（OI-242 の (5)）
- `guides/config.md` の 3 つの規則の前置きは、規則 3 が spec の後始末になったので、列を消すマイグレーションを書く人と、消した列を足し直す spec を書く人の両方を主語にし、規則 1・2 が `ignored_columns` の置き方と外し方、規則 3 が spec の後始末だと書いた。計画の「文書に残すこと」が前置きを規則 3 を含む形に直すと決めている（判断なし）
- 規則 3 の文に、接続の `clear_cache!` がモデルの列の情報を戻さないことと、`reset_column_information` が schema cache の表の分を消すこと（activerecord 8.1.4 の `model_schema.rb`）を書いた。計画の作るもの 2 が引いた原文を、規則の理由として写した（判断なし）

#### RED

期待の不一致で落ちたものは、次の 2 つである。

| spec | 流した版 | 落ちた example | 落ち方 |
|---|---|---|---|
| `spec/platform/spec_order_spec.rb:31` | spec と流す対象を足し、`spec/spec_helper.rb` の設定を注釈から出す前（`7e7b88a` の作業ツリー） | (a)〜(c) の example（2 examples, 1 failure） | `expected nil to be a kind of Integer`（(a) の `seed`） |
| `packs/sales/spec/public/sales/item_prices_backfill_spec.rb:172` | 後始末をメソッドに出して example を書き直し、`Sales::Item` の `ignored_columns` を外す前（同上、`--seed 1`） | 後始末を確かめる example（6 examples, 1 failure） | 対照の `expected ["id", "owner_tenant_id", "code", "name", "unit", "tax_rate_percent", "published", "created_at", "updated_at"] to include "unit_price"` |

`spec/platform/spec_order_spec.rb` の定義の順と違う並びを確かめる example（`:44`）は、`--seed` を渡すので、設定によらず書いた時点で通った。(a)〜(c) の検出力を支える前提（seed が実際に並びを変える）を確かめる example で、RED に代えて下の壊して落ちる記録を持つ。

#### 壊して落ちる記録

壊す前にファイルを一時の置き場に複製し、複製から戻した。数は、壊した版でそこに書いた spec のファイルだけを流した結果である（`5bb8dc7` と同じ木の作業ツリー）。

| 作るもの | 壊し方 | 落ちた example |
|---|---|---|
| 1 | `config.order = :random` を注釈に戻す | `spec_order_spec.rb:31` の (a)（2 examples, 1 failure。`expected nil to be a kind of Integer`） |
| 1 | `Kernel.srand config.seed` を注釈に戻す | 同じ example の (c)（2 examples, 1 failure。`expected: "0.6807487535072207" got: "0.997406095073844"`） |
| 1 | 流す対象のグループに `order: :defined` を付け、seed が並びを変えないようにする（実装レビューの直しの後） | `spec_order_spec.rb:44` だけ（2 examples, 1 failure。`expected: value != ["1", "2", …, "10"]`） |
| 2 | `restore_current_schema` の `Sales::Item.reset_column_information` を外す | 後始末を確かめる example だけ（`--seed 1` で 6 examples, 1 failure。後始末の後の `column_names` に `unit_price` が残る） |
| 2 | `after` から `restore_current_schema` を呼ばない | seed ごとの並び（`--dry-run`）は、seed 1 が `104,127,113,159,172,91`、seed 2 が `91,104,172,159,127,113`、seed 3 が `172,127,159,104,113,91` である。seed 1：最初に流れた `:104` のほかの 5 つ（`:91`・`:113`・`:127`・`:159`・`:172`）とファイルの終わりの `after(:context)`（6 examples, 5 failures, 1 error occurred outside of examples）。seed 2：`:104`・`:113`・`:127`・`:159`・`:172` と `after(:context)`（同じ数）。seed 3：`:91`・`:104`・`:113`・`:159` と `after(:context)`（6 examples, 4 failures, 1 error occurred outside of examples。書き直した example が最初に流れ、example の中で後始末を呼ぶので、次に流れた `:127` も通った）。落ちた example はどれも `before` の `DROP CONSTRAINT` が `constraint "sales_order_lines_matched_together" ... does not exist` で落ち、`after(:context)` は「移行の spec が、items.unit_price を消すか受注明細の CHECK 制約を戻すのを終えていない」で止まった |

最後の壊し方は DB に移行の前の形を残すので、seed ごとに流す前と、戻した後に `TEST_DATABASE=factory_ops_m58_test RAILS_ENV=test bin/rails db:test:prepare` で DB を作り直した。

### 確かめたこと

#### 手元で流したもの

```sh
TEST_DATABASE=factory_ops_m58_test BASE_REF=origin/cycle-11-plan bin/ci   # 5bb8dc7 で、rspec を含むほかの工程は通り、check-schema-compat と check-branch-coverage は基準の ref が無いので落ちた（下の文）
BASE_REF=origin/main bin/check-schema-compat && BASE_REF=origin/main bin/check-branch-coverage   # 5bb8dc7 で通った。スキーマの変更は無く、分岐の網羅率の警告は 0 件
TEST_DATABASE=factory_ops_m58_test BASE_REF=origin/main bin/ci   # 実装レビューの直しの後の 934267a でも、すべての工程が通った。rspec は 3200 examples, 0 failures（Randomized with seed 39611）、分岐の網羅率の警告は 0 件
TEST_DATABASE=factory_ops_m58_test BASE_REF=origin/main bin/ci   # 2ce4ed6（証跡を足した版）で、すべての工程が通った。rspec は 3200 examples, 0 failures（Randomized with seed 29891）、分岐の網羅率の警告は 0 件
(for seed in 1 2 3; do TEST_DATABASE=factory_ops_m58_test bundle exec rspec --seed "$seed" || exit 1; done)   # 5bb8dc7 で、3 つとも 3200 examples, 0 failures
TEST_DATABASE=factory_ops_m58_test bundle exec rspec spec/platform/spec_order_spec.rb packs/sales/spec/public/sales/item_prices_backfill_spec.rb   # 順も seed も渡さずに 8 examples, 0 failures（Randomized with seed 5161）。934267a でも 8 examples, 0 failures
git grep -n 'ignored_columns' -- packs   # 0 件（934267a。この後の commit は証跡だけを変える）
git grep -n -e '外さず' -e '順を乱しておらず' -e 'ignored_columns でこの列' -- docs ':!docs/plans' ':!docs/implementation-plan.md' packs db   # 0 件（934267a。この後の commit は証跡だけを変える）
git grep -n -e 'Import::KINDS' -e 'KINDS = %w\[items stocks\]' -- packs spec app lib   # 0 件（934267a。この後の commit は証跡だけを変える）
bin/check-open-items --due M58 && bin/check-commit-refs   # 通った
```

`bin/ci` を流している間に、計画の PR（#108）が main に入って `cycle-11-plan` のブランチが消え、`origin/cycle-11-plan` が無くなった。基準の ref を読む 2 つの工程だけを、`BASE_REF=origin/main`（分岐点は同じ `7e7b88a`）で流し直し、証跡を足した版で `bin/ci` の全体を流し直した。`5bb8dc7` の `bin/ci` の rspec は全件の印を渡して `--seed` を渡さずに流れ（Randomized with seed 59808）、3200 examples, 0 failures で、呼ばれない公開 API の一覧は出なかった。全件を `--seed` 1・2・3 で流した 3 回は、それぞれ 3 分 48 秒・3 分 28.7 秒・3 分 31.6 秒かかった。rspec の件数は、計画の `7e7b88a` の 3198 から、乱順の 2 つの example で 3200 になった（移行の spec の example は書き直しで、数は変わらない）。`5bb8dc7` の後の commit は、spec と実装をコメントだけ変えたので、全件の 3 つの seed は流し直していない（Claude の系統が `98a94b0` で流し直し、3 つとも 3200 examples, 0 failures だった）。手元では E2E を流していない。変えたファイルが画面にも GraphQL のスキーマにも届かないからで、全体の通過は PR の CI の `e2e` で確かめる。

PR #109 の CI は、push のたびに `pull_request` で流れた（`publish` は `pull_request` なので skip）。流し直しはしていない。

| 先端 | 実行 | 結果 |
|---|---|---|
| `98a94b0` | [39456083566](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/39456083566) | success（`scan_ruby`・`lint`・`test`・`frontend`・`e2e`・`manifests`・`images` が通り、`publish` は skip） |
| `934267a` | [39459840838](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/39459840838) | success（同上） |

この表を載せた commit は証跡だけを変える。その CI の結果は PR の checks で見る。

### 残件の処理

引当先が M58 の行は、OI-239〜OI-241（どれも `judgment`）で、計画のとおりに作った。OI-241 のとおり、OI-106 の内容の欄の末尾に M58 で外したことを書き、`judgment` のまま残した。計画が「実装で決める」とした名前と、計画が書かなかった細部を OI-242 に `judgment` で積んだ。取りまとめ役の判断の受け口（`decisions.md`）は、着手の時と各 commit の前と報告の前に読み、どの時点でも空だった。
