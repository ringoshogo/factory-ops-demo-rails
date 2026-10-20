# サイクル 10 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M57 CI とテストの守りの照らし方を直す：`publish` の `if:` を 1 つの式に一致させて照らす、呼ばれない公開 API を全件で落とす、内部の一覧と GraphQL の enum の一致

`m57-ci-guards`（base は `main`）。サイクル 10 の計画の `cycle-10-plan` の先端 `391a017` から切った。計画の PR（#104）が未マージの間は、その commit も PR の差分に見える。M57 の差分は `391a017..` である。

PR #105 の実装レビューは、実装者が 2 系統に同じ依頼で出した。Codex は Conditional Go、Claude は Go だった。どちらの系統も、`391a017..32743b0` の diff を `git show 32743b0:<パス>` で読んだ。

- Claude：手元で完了条件の rspec を流し（266 examples, 0 failures）、`FULL_SUITE=1` で全件を流した（3193 examples, 0 failures、終了コード 0）。ワークフローに印の無い rspec のステップを足す壊し方と、`publish_condition?` の最初の `strip` を外す壊し方を流した。rspec-core 3.13.6 の `after(:suite)` の積み方と例外の扱いを原文で確かめた
- Codex：読み取り専用で流した。Rails と DB を使う spec は流さず、`ci_checks_spec.rb` を commit の中身に差し替えたメモリの上で流し（35 examples, 0 failures）、最初の `strip` を外しても通ることを確かめた。rspec-core 3.13.6 と graphql-ruby 2.6.11 の縮小の実験で、`after(:suite)` の `Exception` の子の例外で終了コードが 1 になり残りのフックも流れることと、`extra_types` だけの enum が `Schema.types` に載らないことを確かめた

Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High は Codex R1 の 1 件で、直し方が PR の CI の実行と結果を証跡に足すと名指しされた Conditional Go なので、直したことをここに書き、読み直しには出していない。

| 系統 | 判定 |
|---|---|
| Codex | Conditional Go（High 1・Medium 1・Low 1） |
| Claude | Go（Low 2） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R1） | 指摘なし |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R2・R3） | 指摘（R1） |
| 参照の維持 | 指摘なし | 指摘（R2） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex R1 | 手元で E2E を流していないのに、PR の CI の実行と結果（`e2e` の全体の通過）が証跡に無い（`implementation-plan.md`「1 つのマイルストーンの進め方」の 4） | 下の「手元で流したもの」に、`32743b0` と直した版の PR の CI の実行とジョブごとの結果を書いた。`32743b0` の実行で `e2e` を含むすべてのジョブが通った | この節を載せた commit |
| Medium | Codex R2 | enum の組ごとの 11 の example のうち、壊して落ちる記録があるのは 2 組だけで、残る 9 組は RED にも壊して落ちる記録にも代わるものが無い | 残る 9 組の enum の型から値を 1 つずつ消し、どれもその組の example だけが落ちることを確かめた（下の壊して落ちる記録の表） | 同上 |
| Low・Low | Codex R3・Claude R1 | `publish_condition?` の最初の `strip` を外しても、式の表のどの行も落ちない。通す行に、`${{ }}` の外側に空白を持つ式が無い | 通す行に `"  ${{ success() && github.event_name == 'push' }}  "` を足した。最初の `strip` を外すとこの行だけが、2 つ目の `strip` を外すと `${{ }}` で囲んだ 2 行が落ちる（下の表） | 同上 |
| Low | Claude R2 | `config.md` の「`success()` をほかの状態の関数か演算子と組み合わせた式は、… 流れて push しうる」が、許す式（`success()` を `&&` と組み合わせる）も危ない側に入れて読める | 「守りは、明示した `success()` が偽のときに式全体が偽になる形でだけ効き、そうでない形は流れて push する」と、危ない形の条件で書き直した | 同上 |

違和感は次のように扱った。

- Claude 1：台帳の OI-230 が比べる 10 個・比べない 9 個のままで、OI-230 だけを読むと古い分け方を正と取りうる → OI-230 の内容の末尾に、M57 で 11 個と 8 個に変えたこと（OI-235）を足した
- Claude 2：`guides/testing.md` と `showcase.md` の層の件数を数える例が、全件を流すのに印を渡さない → 両方の例に `FULL_SUITE=1` を足した
- Claude 3：`extra_types` で足した enum の型は一致の spec の外になることが、コメントにも spec にも無い → `enum_values_spec.rb` の型を集める `let` のコメントに、`extra_types` の型は載らず、スキーマは `extra_types` を使わないので漏れないことを書いた
- Codex：なし

### 実装の記録

下の spec の行の番号は、実装レビューに出す版のものである。

#### 計画との違い

- 前提にした計画の数は、作るもの 3 の 1 つを除いて実物と合っていた。計画レビューの時点の enum の型は 19 個で、着手の時にも 19 個だった。作るもの 2 の着手の時点の全件（`391a017` に作るもの 1 の spec の直しだけを入れた作業ツリー、`TEST_DATABASE=factory_ops_m57_test bundle exec rspec --format progress`）は 3177 examples, 0 failures で、呼ばれない公開 API の一覧は出なかった（0 個）。足した spec は無い（判断なし）
- 作るもの 3 の並べ替えの列の 5 個のうち `StockOrderFieldType` を、比べない側から比べる側に移した（比べる 11 個・比べない 8 個）。計画は 5 個とも「列の式の表は操作者から作る private のメソッドで、定数の一覧が無い」としたが、在庫の一覧だけは公開 API の定数 `Inventory::Stocks::ORDER_COLUMNS` が並べてよい列を持ち、`Inventory::Stocks.list` が `Page::Sort.of` にそのまま渡す。計画の「比べる相手は値を受け付けるコードが読む一覧」「比べる組は手で選ばない」に合わせ、`implementation-plan.md` M57 の作るもの 3 を直した（OI-235）
- 計画が「実装で決める」とした名前：全件の印は `FULL_SUITE=1`、判定のメソッドは `PublicApiReturns.verify_called!`、`if:` の補助は `ci_checks_spec.rb` の `publish_condition?` と `publish_condition`、公開 API の別名は `Purchasing::PurchaseOrders::STATUSES`・`TIMELINE_KINDS`、`Sales::SalesOrders::STATUSES`、`Fulfillment::ShipmentRequests::STATUSES`、`Inventory::Stocks::MOVEMENT_EFFECTS`、並べる向きは `Page::Sort::DIRECTIONS` にした（OI-234 の (1)・(3)・(4)）
- `Page::Sort::DIRECTIONS` は、`Data.define` のブロックの中ではなく、ブロックの後で `Sort` に置いた。ブロックの中の定数の代入は、レキシカルな外側の `Page` に付くからである。`of` は `Sort::DIRECTIONS` を読む（OI-234 の (4)）
- 作るもの 2 の子のプロセスで流す小さい spec のファイルは、`spec/fixtures/public_api_returns/one_example.rb` に置き、名前を `*_spec.rb` にしなかった。全件の流れに入れないためで、パスを名指しすれば rspec は読む。子には親の `TEST_DATABASE` を渡し、`COVERAGE` は渡さない。渡すと子が親の `tmp/coverage.json` を書き換えるからである（OI-234 の (2)）
- 作るもの 2 の判定のメソッドの example は、呼ばれなかった名前の一覧を引数で渡して確かめる。初めは試しのモジュールを確かめる対象にして `uncalled` から読ませたが、同じファイルの前の example が試しのモジュールを呼ぶので、`uncalled` に載らず落ちた（OI-234 の (1)）
- 作るもの 3 の比べ方は、enum の `value:` と一覧の要素のどちらも `to_s` した集合にした。状況の一覧は記号、権限と在庫の調整の一覧は文字列で持つからである（OI-234 の (5)）
- 作るもの 2 の `ci_checks_spec.rb` の期待で、spec のパスは `spec/` か `packs/` で始まる語として見分ける。`--out tmp/rspec.json` の値をパスと取り違えないためで、spec を置く場所はこの 2 つだけである（判断なし）
- 作るもの 2 の共通の完了条件の行の末尾に、`FULL_SUITE` を足したマイルストーンのコメントを、ほかの行と同じ形で足した（判断なし）
- 作るもの 3 の壊し方の「enum の型を 1 つ足してスキーマに載せる」は、`extra_types` では `FactoryOpsSchema.types` に載らず、何も落ちなかった。`Viewer` のフィールドの型にして載せると落ちた（下の表）。スキーマのコメントが `extra_types` を使わないと決めているので、spec は変えていない（判断なし）
- 計画の「文書に残すこと」のほかに、`showcase.md` のテーマ 8 の表の公開 API の戻り値のガードの行に全件の印を、表に enum の一致の行を足した。テーマ 8 は、機械で守る規約をすべて表に挙げるからである（判断なし）

#### RED

期待の不一致で落ちたものは、次の 3 つである。

| spec | 流した版 | 落ちた example | 落ち方 |
|---|---|---|---|
| `spec/platform/ci_checks_spec.rb` の式の表 | 式の表の example を足し、補助 `publish_condition?` の本体をいまの 6 つの期待（と `success_inside_call?`・`without_strings`）にした版 | 改善の探索の表の 3 つの迂回（`[1:23]`・`[1:24]`・`[1:25]`）と `${{ github.event_name == 'push' && success() }}`（`[1:28]`）の 4 つ（33 examples, 4 failures） | `expected false got true` |
| `spec/platform/ci_checks_spec.rb:167`（全件の印） | 期待を足し、3 か所に `FULL_SUITE=1` を渡す前 | この example（35 examples, 1 failure） | `expected: {"config/ci.rb" => ["1"], "workflow" => ["1"], "共通の完了条件" => ["1"]} got: {"config/ci.rb" => [nil], "workflow" => [nil], "共通の完了条件" => [nil]}` |
| `spec/graphql/enum_values_spec.rb:40` | spec を足し、公開 API の別名と `Page::Sort::DIRECTIONS` を出す前 | この example（12 examples, 7 failures のうち期待の不一致はこれだけ） | `expected: [] got: ["Types::PurchaseOrderStatusType", "Types::PurchaseOrderTimelineKindType", "Types::OrderDirectionType", "Types::SalesOrderStatusType", "Types::ShipmentRequestStatusType", "Types::StockMovementKindType"]` |

同じ版で、`enum_values_spec.rb` の組ごとの example のうち定数の無い 6 つは `NameError` で落ちた。読み込みの失敗なので RED に数えず、下の壊して落ちる記録で代える。定数のあった 5 つ（在庫の調整・在庫の並べ替えの列・取り込みの種類・権限・ユーザーエラーのコード）は通った。

次の spec は、足したメソッドが無いと読み込みの失敗でしか落ちないので、壊して落ちる記録で RED に代える。

- `spec/platform/public_api_returns_spec.rb:149`（判定のメソッドが印の有無で落とすか一覧を出すだけか）と `:161`（子のプロセスで流す、ガードの example）
- `spec/platform/ci_checks_spec.rb:185`（全件を流す rspec を拾う補助の example）
- `spec/graphql/enum_values_spec.rb` の組ごとの 11 の example（11 組すべてを壊して落とした）

#### 壊して落ちる記録

壊す前にファイルを一時の置き場に複製し、複製から戻した。数は、壊した版でそこに書いた spec のファイルだけを流した結果である。作るもの 1 の行は、作るもの 2 の example を足す前の版で流したので、`publish` の example の行の番号は `:99` だった（いまの `:112`）。

| 作るもの | 壊し方 | 落ちた example |
|---|---|---|
| 1 | `publish_condition?` が続く空白を 1 つにしない | 式の表の通す行の空白の数だけが違う式（`[1:32]`）だけ（33 examples, 1 failure） |
| 1 | `publish_condition?` が全体を囲む `${{ }}` を外さない | 式の表の通す行の `${{ }}` で囲んだ式（`[1:31]`）だけ（33 examples, 1 failure） |
| 1 | `publish_condition?` の最初の `strip` を外す（実装レビューの直しの後） | 式の表の通す行の `${{ }}` の外側に空白を持つ式（`[1:33]`）だけ（36 examples, 1 failure） |
| 1 | `publish_condition?` の 2 つ目の `strip` を外す（同上） | 式の表の通す行の `${{ }}` で囲んだ 2 つ（`[1:31]`・`[1:33]`）（36 examples, 2 failures） |
| 1 | 一致ではなく、そろえた値が `success()` を含めば通す | 式の表の落とす行の 22 のうち、`Success() && …` のほかの 21（33 examples, 21 failures） |
| 1 | `ci.yml` の `test` のジョブに `if: github.event_name == 'pull_request'` を足す | `publish` の example だけ（33 examples, 1 failure） |
| 1 | `ci.yml` の `publish` の `if:` を `success() && github.event_name == 'push' \|\| always()` にする | `publish` の example だけ（33 examples, 1 failure） |
| 2 | `verify_called!` が印を見ずにいつも例外にする | `public_api_returns_spec.rb:149`・`:161`（8 examples, 2 failures。流したファイル自身の `after(:suite)` も、印が無いのに例外にした） |
| 2 | `verify_called!` が印があっても例外にしない | `public_api_returns_spec.rb:149`・`:161`（8 examples, 2 failures） |
| 2 | `rails_helper.rb` の `after(:suite)` から `verify_called!` の呼び出しを外す | `public_api_returns_spec.rb:161` だけ（8 examples, 1 failure） |
| 2 | `config/ci.rb`・ワークフロー・共通の完了条件から `FULL_SUITE` を外す（1 つずつ） | どれも `ci_checks_spec.rb:167` だけ（35 examples, 1 failure） |
| 3 | `Inventory::Adjustment::TYPES` に `transfer` を足す | `enum_values_spec.rb` の `StockAdjustmentType` の組（`[1:6]`）だけ（12 examples, 1 failure） |
| 3 | `OrderDirectionType` から `DESC` を消す | `enum_values_spec.rb` の `OrderDirectionType` の組（`[1:12]`）だけ（12 examples, 1 failure） |
| 3 | 残る 9 組の enum の型から、最後の値を 1 つずつ消す（`PurchaseOrderStatusType` の `SENT`・`SalesOrderStatusType` の `RECEIVED`・`ShipmentRequestStatusType` の `READY`・`PurchaseOrderTimelineKindType` の `INVOICE_RECEIVED`・`StockMovementKindType` の `SHIP`・`StockOrderFieldType` の `ITEM_NAME`・`ImportKindType` の `STOCKS`・`PartnershipPermissionType` の `VIEW_SHIPMENTS`・`UserErrorCodeType` の `CONFLICT`。実装レビューの直しの後） | どれもその組の example（`[1:2]`〜`[1:5]`・`[1:7]`〜`[1:11]`）だけ（12 examples, 1 failure） |
| 3 | enum の型 `Types::ProbeKindType` を足し、`Viewer` のフィールドの型にしてスキーマに載せ、組にも表にも書かない | `enum_values_spec.rb:40` だけ（12 examples, 1 failure。`got: ["Types::ProbeKindType"]`） |

落ちなかったもの：enum の型を `extra_types` でスキーマに足したときは、何も落ちなかった（上の「計画との違い」）。

#### 配線を変えた人の手の確かめ

作るもの 2 はワークフローの `env` と `config/ci.rb` の工程を変えたので、`guides/config.md`「CI の工程」の規則のとおり、落ちるべき変更を作業ツリーに入れて、CI と同じコマンドで落ちることを手で確かめた。どの spec も呼ばない公開 API（`Inventory::Stocks.m57_probe`）を作業ツリーに足し、`TEST_DATABASE=factory_ops_m57_test COVERAGE=1 FULL_SUITE=1 bundle exec rspec --format progress --format json --out tmp/rspec.json` を流した。3193 examples, 0 failures, 1 error occurred outside of examples で、終了コードは 1 だった。出力は「どの spec も呼ばなかった 1 個は確かめの外: Inventory::Stocks.m57_probe」で、`COVERAGE` の `after(:suite)` も流れて、`tmp/coverage.json` と `tmp/rspec.json` が流し終えた時刻で書かれた。足した公開 API は複製から戻した。

作るもの 1 は `publish` の `if:` そのものを変えないので、この確かめは要らない（計画の「判断」）。

### 確かめたこと

#### 手元で流したもの

```sh
TEST_DATABASE=factory_ops_m57_test BASE_REF=origin/cycle-10-plan bin/ci   # 7c3cfd4 で、すべての工程が通った。rspec は 3193 examples, 0 failures
bin/check-open-items --due M57 && bin/check-commit-refs   # 通った
bundle exec rspec spec/platform/ci_checks_spec.rb spec/platform/public_api_returns_spec.rb spec/graphql   # 0 failures
git grep -n -e success_inside_call -e without_strings -- . ':!docs/plans' ':!docs/implementation-plan.md'   # 0 件
git grep -n -F -e "format('{0}', success())" -- docs/guides docs/showcase.md .github   # 0 件
```

`bin/ci` の rspec は全件の印を渡して流れ、呼ばれない公開 API の一覧は出なかった（0 個）。分岐の網羅率の警告は、基準 `391a017` で 0 件だった。`bin/packwerk validate && bin/packwerk check` は、公開 API の別名を spec から読むので違反が増えず、通った。rspec の件数は、計画の `391a017` の 3152（`bundle exec rspec --dry-run`）から 3193 になった（作るもの 1 の式の表の 25、全件の印の期待と補助の 2、判定と子のプロセスの 2、enum の 12）。画面と E2E は、変えたファイルが画面にも GraphQL のスキーマにも届かないので流していない。

### 残件の処理

引当先が M57 の行は、OI-229・OI-230（どちらも `judgment`）で、計画のとおりに作った。OI-230 の (2) の分け方は、`StockOrderFieldType` を比べる側に移したので、OI-235 に `judgment` で積んだ。計画が「実装で決める」とした名前と形を OI-234 に `judgment` で積んだ。取りまとめ役の判断の受け口（`decisions.md`）は、着手の時と各 commit の前と報告の前に読み、どの時点でも空だった。
