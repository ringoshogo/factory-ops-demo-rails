# サイクル 9 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M52 テストの基盤と CI の守りのガードを足す：E2E の起動の時の読み込み、`publish` の `if:`、テナントで包む around

`m52-test-guards`（base は `main`）。サイクル 09 の計画の `cycle-09-plan` の先端 `9fbe840` から切った。計画の PR が未マージの間は、その commit も PR の差分に見える。M52 の差分は `9fbe840..` である。

Codex は Conditional Go、Claude は Go だった。どちらの系統も、`9fbe840..88c2f43` の diff を `git show 88c2f43:<パス>` で読んだ。Claude は手元で `tenant_example_spec.rb` と競合テストを続けて流し、`publish` の `if:` の期待を式ごとに Ruby で照らし、引用の原文を手元の gem で確かめた。Codex は spec と E2E を流さず、照らし方を Ruby で確かめ、引用の原文を確かめた。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。

Codex の R1 が High だったので、直した版を 2 系統の読み直しに出した（下の「読み直し 1」）。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Conditional Go（High 1・Medium 1） | 読み直し 1（下） |
| Claude | Go（Medium 3・Low 2） | 読み直し 1（下。Codex の High の直しを見るため、同じ依頼で出した） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘（R1・R2） |
| 正しさ | 指摘（R1） | 指摘なし |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R1） | 指摘（R3・R4・R5） |
| 参照の維持 | 指摘（R2） | 指摘（R2） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex | R1：`false == success() && github.event_name == 'push'` が `publish` の `if:` の期待をすべて通る | 直後を照らす期待を、契機の比べを除いた残りが `==` を含まない期待に替えた。この式と `success() == false && …` の両方で落ち、`${{ github.event_name == 'push' && success() }}` は通ることを確かめた。計画の作るもの 2 と表、`config.md`「CI の工程」、spec の前のコメントを直した | この節を載せた commit |
| Medium | Claude | R3：同じく左での比べと、括弧ごとの比べを通す | Codex R1 と同じ直しで、どちらも `==` が残るので落ちる | 同上 |
| Low | Claude | R4：`\S{0,2}` が迂回でない式（`${{ … && success() }}`・`(success())`）を落とす | Codex R1 の直しで直後を照らす期待を外した | 同上 |
| Medium | Codex・Claude | R2：`example.run` の前の送出を範囲外にした理由（止まらずに落ちる）が、後ろが競合テストなら止まるという実装で分かった事実と合わない | 計画の M52「範囲外」と `testing.md`「層への配分」の文を、後ろが行列のグループなら落ち、競合テストなら止まる形に直した。範囲外のままにした判断と、作者に確かめ直すことを OI-214（`judgment`）に積んだ。作者が確かめた OI-209 の行は書き換えていない | 同上 |
| Medium | Claude | R1：完了条件の `git grep` が、`ec7aedc` で足した `handoff.md` の文に当たる | `handoff.md` の文をファイル名を書かない形にした。この節を載せた版で 0 件であることを確かめた | 同上 |
| Low | Claude | R5：ガードの glob の対照が `packs/` の側だけを見る | `spec/` の側にも `TenantExample.run` の around が 1 つ以上あることを対照に足した。glob の片方ずつを外すと落ちることを確かめた（上の表） | 同上 |

違和感は次のように扱った。

- Claude 1：状態の関数の期待が小文字だけを見る → IB-141
- Claude 2：`TenantExample.run` より内側の around の送出も後始末を飛ばす → IB-142
- Claude 3：OI-208 の内容の欄の末尾の、書いた場所の説明 → 消した（同じ説明は「計画との違い」にある）
- Claude 4：M54 のブランチも #85 を祖先に持たず、作るもの 8 がまた移る → IB-143
- Codex 1：`\S{0,2}` が安全な式を落とす → Codex R1 の直しで外した

#### 読み直し 1

`d45c1a5`（初回の指摘の直し）を、2 系統に同じ依頼で出した。どちらの系統も、`88c2f43..d45c1a5` と `9fbe840..d45c1a5` を `git show d45c1a5:<パス>` で読み、`publish` の `if:` の期待を Ruby で書き写して式ごとに照らした。spec は流していない。Claude のサブエージェントは最終報告を返さずに終わり、結果のファイルから読んだ。

| 系統 | 判定 | 前の指摘 |
|---|---|---|
| Codex | Conditional Go（High 1） | R1・R2 とも解消 |
| Claude | Conditional Go（High 1・Medium 1） | R1〜R5 とも解消 |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘なし |
| 正しさ | 指摘（N1） | 指摘なし |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（N1） | 指摘（N1・N2） |
| 参照の維持 | 指摘なし | 指摘（N1） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex・Claude | N1：`==` だけを照らすので、大小の比べ（`success() < 1`・`success() >= false`・`1 > success()`）が期待をすべて通る。`needs` が落ちると `success()` は偽で、GitHub の型の変換で 0 になり真になる。直す前の直後を照らす形は `success() < 1` を落としていた | 契機の比べを除いた残りが比べの演算子の文字（`=`・`<`・`>`）を含まない期待に替えた。3 つの式で落ち、迂回でない 2 つの式で落ちないことを確かめた（上の表） | この節を載せた commit |
| Medium | Claude | N2：`format('{0}', success())`・`toJSON(success())`・`contains('truefalse', success())` のように関数の引数に入れて真の値に変える式が通る | 名前の付いた括弧の中に `success()` が無い期待を足した。含む・含まないで照らす方針のまま止められたので、同じマイルストーンで直した。3 つの式で落ちることを確かめた | 同上 |

違和感は次のように扱った。

- Claude 1：`success() >= false` の評価は GitHub の文書の型の変換から読んだもので、同じ型の真偽値どうしの比べは確かめていない → 判定に関わらない。直した期待は大小の比べの演算子の文字ごと落とすので、評価の結果によらず落ちる
- Claude 2：契機の比べの除き方が単一引用符の文字列だけを見る → GitHub の式は単一引用符しか文字列にしないので、扱わない
- Codex：なし

直した後の版を読み直し 2 に出した（下）。

#### 読み直し 2

`fddcd93`（読み直し 1 の指摘の直し）を、2 系統に同じ依頼で出した。どちらの系統も `git show fddcd93:<パス>` で読み、6 つの期待を Ruby で書き写して式ごとに照らした。spec は流していない。Claude のサブエージェントは最終報告を返さずに終わり、結果のファイルから読んだ。

| 系統 | 判定 | 前の指摘 |
|---|---|---|
| Codex | Conditional Go（High 1） | N1 は解消、N2 は未解消（F1） |
| Claude | Conditional Go（Medium 1） | N1 は解消、N2 は一部未解消（M1） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（F1） | 指摘なし |
| 正しさ | 指摘（F1） | 指摘（M1） |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（F1） | 指摘（M1） |
| 参照の維持 | 指摘（F1） | 指摘（M1） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex | F1：括弧の中の `success()` を照らす期待が最初の `)` までしか見ないので、`format('){0}', success())` と `format('{0}{1}', toJSON(github.event_name), success())` が通る。どちらも `needs` が落ちても空でない文字列で真になる | 単一引用符の文字列を空にしてから括弧の深さを数え、`success()` を囲む括弧のどれかが関数の呼び出しの括弧か添字なら落とす補助（`success_inside_call?`）に替えた。2 つの式と Claude M1 の 4 つの式で落ち、対照の 3 つで落ちないことを確かめ、補助の 2 つの処理を片方ずつ外すと迂回が通ることも確かめた（上の表） | この節を載せた commit |
| Medium | Claude | M1：同じ穴（`format(')', success())`・`join(fromJSON('[1]'), success())`・`fromJSON('[1,1]')[success()]` など） | Codex F1 と同じ直しで落ちる | 同上 |

読み直しは 2 回までなので、この直しは読み直しに出していない。直しが閉じたかは、上の表の壊し方で確かめた。

違和感は次のように扱った。

- Claude 1：比べの演算子の文字の期待が、ほかの文字列の中の `=` も落とす → 同じ直しで、文字列を空にしてから照らす形にした（対照の `contains(github.ref, '=')` が通る）
- Claude 2：契機の比べの除き方が `''` を扱わない → 文字列を空にする処理は `''` を扱う形にした
- Codex 1：照らし方が式の構文解析に近づいている → IB-144

### 実装の記録

#### 計画との違い

- 作るもの 3（OI-208）は作らず、M54 の作るもの 8 に移した。計画は、作るもの 1・2・4 の先端で `git merge origin/main` を流して #85 を取り込んでから書くとしたが、マージのコマンドが実行の環境の権限で拒否された（`a2c8225` で `bin/ci` を通した後）。別の手で取り込まずに取りまとめ役に返し、作者が 2026-10-16 に、M52 から外し #85 を祖先に持つブランチで行うと決めた（受け口の D-1）。M52 のブランチに main のマージの commit は無く、差分は `9fbe840..` の 1 つの範囲である。計画の M52 の節（目的・作る順・作るもの 3・依存の表・実装する文書の節）と、M54 の節（作るもの 8・依存の表・実装する文書の節）と、`guides/dev-cycle.md`「全体の流れ」の表のサイクル 09 の行を直した。OI-208 は引当先を M54 にし、作者の判断を内容の欄の末尾に書いた。受け口は結果の欄に書くよう求めたが、`bin/check-open-items` が `open` の行の結果を落とすので、内容の欄にした
- 作るもの 4 の止まりを再現する example の後始末は、計画の「`ensure` で両方の接続を巻き戻す」では足りなかった。(i) の対照で内側の example の around が送出すると、rspec-rails の `after_teardown` が飛び、トランザクションのほかに、example の間だけスレッドをまたいで共有させた接続（activerecord 8.1.4 の `lib/active_record/test_fixtures.rb` の `teardown_transactional_fixtures` が呼ぶ `ConnectionPool#unpin_connection!`）も戻らない。接続を巻き戻すだけの形で `spec/platform/tenant_example_spec.rb` と `packs/sales/spec/concurrency/sales/cancellation_reviews_lock_spec.rb` を `--order defined` で続けて流すと、競合テストの 2 つのスレッドが同じ接続を使い、プロセスが CPU を使わずに 10 分を過ぎても終わらなかった。アプリの接続は `idle in transaction`（最後の問い合わせ `SELECT pg_backend_pid()`）だった。example を 1 つずつ前に置いて流し、(i) の後だけで止まることを確かめた。後始末を、内側の example の `after_teardown` を流してから両方の接続を巻き戻す形にし、同じ 2 つのファイルが 7 examples, 0 failures で終わることを確かめた。計画の作るもの 4 の節を直した（`99545f4`）。同じ事実を `spec/support/tenant_example.rb` の冒頭のコメントにも書いた。M51 の後に止まりが「トランザクションが残っている」で落ちる形に変わったのは後ろのグループが行列のグループだったときで、後ろが競合テストなら、飛んだ後始末は今も止まりになる。
- 作るもの 2 の壊し方のうち、否定の 2 つ（`!success() && …`・`!(success() && …)`）は、`if:` の値を `!` で書き始めると YAML のタグとして読まれ、`ci_checks_spec.rb` の全 example が `YAML.load_file` の失敗で落ちる。`if:` の期待を確かめたことにならないので、GitHub の式の書き方の `${{ }}` で包んで流した。計画の壊して落ちる記録の表を直した（`a2c8225`）。
- 作るもの 2 の `success()` を比べないことの照らし方は、計画の「`success()` の直後が `&&` か式の終わり」から、契機の比べ（`github.event_name == '…'`）を除いた残りが比べの演算子の文字（`=`・`<`・`>`）を含まない形に替え、`success()` を囲む括弧に関数の呼び出しの括弧も添字も無いことを足した。どちらも、単一引用符の文字列を空にしてから照らし、関数の括弧は深さを数える。直後を照らす形は、`false == success() && …` のように左に比べを置く形を通し、`${{ github.event_name == 'push' && success() }}` のように迂回でない式を落とした（実装レビューの Codex R1・Claude R3・R4）。`==` だけを照らす形は大小の比べ（`success() < 1`）を通し、関数の引数に入れる形（`format('{0}', success())`）は比べの照らし方では落ちなかった（読み直し 1 の Codex N1・Claude N1・N2）。関数の括弧を最初の `)` まで正規表現で見る形は、文字列の中の `)` か前の引数の呼び出しで切れた（読み直し 2 の Codex F1・Claude M1）。計画の作るもの 2 と壊して落ちる記録の表を直した

#### RED と、壊して落ちる記録

どれも `TEST_DATABASE=factory_ops_m52_test` で、Ruby 3.4.11・PostgreSQL 18 で流した。

RED（期待の不一致で落ちたもの）は、作るもの 4 の数え上げのガードである。`9fbe840` の作業ツリーで補助とその spec を外し、`spec/platform/tenant_example_spec.rb` にガードの example だけを置き、18 個の around を書き換える前に流した（1 example, 1 failure。`aggregate_failures` の 2 つ）。

- 対照の `packs/` の下の `TenantExample.run` を呼ぶ around の数が `expected: >= 1 got: 0`
- 直に包む around の一覧が、次の 18 個（17 ファイル）で `expected: []` に合わなかった

```text
packs/fulfillment/spec/models/fulfillment/shipment_request_status_spec.rb:11
packs/fulfillment/spec/public/fulfillment/instructions_spec.rb:9
packs/fulfillment/spec/public/fulfillment/shipping_spec.rb:9
packs/inventory/spec/models/inventory/stock_spec.rb:8
packs/inventory/spec/public/inventory/adjustment_spec.rb:10
packs/inventory/spec/public/inventory/adjustment_spec.rb:45
packs/inventory/spec/public/inventory/allocation_spec.rb:11
packs/purchasing/spec/models/purchasing/purchase_order_status_spec.rb:11
packs/sales/spec/db/item_prices_constraints_spec.rb:9
packs/sales/spec/models/sales/item_price_spec.rb:9
packs/sales/spec/models/sales/sales_order_status_spec.rb:11
packs/sales/spec/public/sales/cancellation_reviews_spec.rb:10
packs/sales/spec/public/sales/catalog_spec.rb:12
packs/sales/spec/public/sales/item_prices_spec.rb:25
packs/sales/spec/public/sales/order_allocation_spec.rb:9
packs/sales/spec/public/sales/order_cancellation_spec.rb:10
packs/sales/spec/public/sales/part_mappings_spec.rb:9
packs/sales/spec/public/sales/purchase_order_translator_spec.rb:12
```

数は計画レビューの数え上げ（18 個）と一致した。書き換えた後は、どちらの期待も通る。

作るもの 1・2 は M51 が作ったものに足すガードで、書いた時点で通った。作るもの 4 の (i)〜(iv) は `TenantExample` が無いと読み込みの失敗でしか落ちない。次の壊して落ちる記録で RED に代える。壊す前にファイルを一時の置き場に複製し、複製から戻した。

| 作るもの | 壊し方 | 結果 |
|---|---|---|
| 1 | `test.rb` の条件から `E2E_EAGER_LOAD` を外す（`ENV["CI"].present?` だけにする） | `e2e_eager_load_spec.rb` の渡したときに真になる example だけが `expected true got false` で落ちた（2 examples, 1 failure） |
| 1 | `start-rails.sh` の `export E2E_EAGER_LOAD=1` の行を消す | スクリプトの行の example だけが `expected: not nil got: nil` で落ちた（2 examples, 1 failure） |
| 2 | `if:` を `${{ !success() && github.event_name == 'push' }}` にする | `publish` の `if:` の example だけが `not_to include("!")` で落ちた（8 examples, 1 failure） |
| 2 | `if:` を `${{ !(success() && github.event_name == 'push') }}` にする | 同じ example だけが `not_to include("!")` で落ちた |
| 2 | `if:` を `success() \|\| github.event_name == 'push'` にする | 同じ example だけが `not_to include("\|\|")` で落ちた |
| 2 | `if:` を `success() == false && github.event_name == 'push'` にする | 同じ example だけが、契機の比べを除いた残りの比べの演算子の文字の期待（`:125`）で落ちた |
| 2 | `if:` を `false == success() && github.event_name == 'push'` にする | 同じ example だけが、同じ期待で落ちた |
| 2 | `if:` を `success() >= false && …`・`success() < 1 && …`・`1 > success() && …` にする（3 つを 1 つずつ） | どれも同じ example だけが、比べの演算子の文字の期待（`ci_checks_spec.rb:125`）で落ちた |
| 2 | `if:` を `format('{0}', success()) && …`・`toJSON(success()) && …`・`contains('truefalse', success()) && …`・`format('){0}', success()) && …`・`format('{0}{1}', toJSON(github.event_name), success()) && …`・`join(fromJSON('[1]'), success()) && …`・`fromJSON('[1,1]')[success()] && …` にする（7 つを 1 つずつ） | どれも同じ example だけが、`success()` を囲む括弧の期待（`ci_checks_spec.rb:126`）で落ちた |
| 2 | `success_inside_call?` の文字列を空にする処理を外し、`format('){0}', success()) && …` にする | 何も落ちなかった（守りが外れたことを、迂回が通ることで確かめた） |
| 2 | `success_inside_call?` の閉じ括弧で 1 段だけ戻す処理を、全部を戻す形にし、`format('{0}{1}', toJSON(github.event_name), success()) && …` にする | 何も落ちなかった（同上） |
| 2（対照） | `if:` を `${{ github.event_name == 'push' && success() }}`・`(success()) && github.event_name == 'push'`・`success() && github.event_name == 'push' && contains(github.ref, '=')` にする | 何も落ちなかった（どれも 8 examples, 0 failures） |
| 4 | ガードの glob を `packs/*/spec` だけにする | ガードの example が `spec/` の対照で落ちた |
| 4 | ガードの glob を `spec` だけにする | ガードの example が `packs/` の対照と直に包む around の一覧で落ちた |
| 4 | `TenantExample.run` から `raise ActiveRecord::Rollback …` の行を外す | (ii)・(iii) が落ちた（5 examples, 2 failures） |
| 4 | 巻き戻しの条件から `pending_exception` を外す | (iii) だけが落ちた（5 examples, 1 failure） |
| 4 | 巻き戻しの条件を外し、いつも巻き戻す | (iv) だけが落ちた（5 examples, 1 failure） |
| 4 | ガードが探す呼び出しの名前から `with_tenant` を外す | ガードの example が合成のソースの対照で落ちた（5 examples, 1 failure） |
| 4 | 同じく `transaction` を外す | 同上 |
| 4 | 探す around の名前から `prepend_around` を外す | 同上 |
| 4 | 同じく `append_around` を外す | 同上 |

M50 の壊し方（`packs/sales/app/public/sales/item_prices.rb` の `Sales::ItemPrices.today_price` の式から `.current` を外す）で `bundle exec rspec packs/sales/spec/public/sales/catalog_spec.rb` を流した。

| 版 | 結果 |
|---|---|
| 直す前（補助を外し、`catalog_spec.rb` の around を `Tenancy.with_tenant` で直に包む形に戻した版） | 19 examples, 3 failures。壊した example（`catalog_spec.rb:119`）のほかに、後ろの `cross_read!` の 2 つのグループ（`:225`・`:252`）が「所有ロールの接続にトランザクションが残っている（1 段）」で落ちた |
| 直した後（`99545f4` の作業ツリー） | 19 examples, 1 failure。落ちたのは壊した example（`:119`）だけ |

### 確かめたこと

#### 手元で流したもの

```sh
TEST_DATABASE=factory_ops_m52_test bundle exec rspec spec/platform/e2e_eager_load_spec.rb spec/platform/ci_checks_spec.rb spec/platform/tenant_example_spec.rb   # 0 failures
git grep -n -e AroundHookErrors -e around_hook_errors -- . ':!docs/plans' ':!docs/implementation-plan.md'   # 実装レビューの直しを載せた版で 0 件（`ec7aedc` と `88c2f43` では handoff.md の 1 件があった。Claude R1）
TEST_DATABASE=factory_ops_m52_test bin/ci   # a2c8225 と ec7aedc で、すべての工程が通った。rspec はどちらも 3122 examples, 0 failures
TEST_DATABASE=factory_ops_m52_test bin/check-open-items --due M52 && bin/check-commit-refs   # ec7aedc で通った
cd frontend && E2E_DATABASE=factory_ops_m52_e2e PLAYWRIGHT_CHANNEL=chrome npm run test:e2e   # ec7aedc で、下の 3 回（Node 22、npm ci の後）
```

分岐の網羅率の警告は、`a2c8225`・`ec7aedc`・`7b29e31` の `bin/ci` でどれも 0 件だった。実装レビューの直しの後の `7b29e31` でも `TEST_DATABASE=factory_ops_m52_test bin/ci` が通った（3122 examples, 0 failures）。直しは spec と文書だけで、E2E は流し直していない。

PR #98 の CI は、push のたびに `pull_request` で流れ、どれも通った（`publish` は `pull_request` なので skip）。流し直しはしていない。

| 先端 | 実行 | 結果 |
|---|---|---|
| `88c2f43` | [38860716691](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38860716691) | success |
| `d45c1a5` | [38861758941](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38861758941) | success |
| `fddcd93` | [38862438055](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38862438055) | success |
| `7b29e31` | [38863167810](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38863167810) | success（e2e 3 分 42 秒・test 5 分 24 秒） |

この表を載せた commit は証跡だけを変える。その CI の結果は PR の checks で見る。

手元の E2E は 3 回流した。1 回目は、ほかの作業で 1 分の load average が 110 に達した間に、`admin-only.spec.ts:24`（受注詳細の取消と審査）がブラウザの文脈を作る `browser.newContext` のまま 60 秒の時間切れで落ちた（1 failed・26 skipped・71 passed、2.4 分）。テストの手順に入る前の、ブラウザを起こす段の時間切れである。load average が 10 前後に下がってから続けて 2 回流し、どちらも 72 passed・26 skipped（1.1 分・1.3 分）だった。M52 は画面とサーバーのコードを変えていない。

### 残件の処理

引当先が M52 の行は、着手の前と PR の前に台帳を読んだ。OI-207 は `a2c8225` で閉じた。OI-205・OI-209（どちらも `decided`）は作るもの 4 で反映した。OI-208 は作者の判断（受け口の D-1）で引当先を M54 に移した。IB-123 の反映先を `tenant_example.rb` に書き換え、IB-136 の結果の欄に、補助を外したので前提が無くなったことを書き足した。IB-134 は作るもの 2 で実装した。OI-214（`judgment`）を実装レビューで積み、IB-141〜IB-143 に違和感を移した。IB-138 は、計画のとおり、サイクル 09 の末の改善の探索で取りまとめ役が判定する。取りまとめ役の判断の受け口（`decisions.md`）で D-1 を読んだ。

## M53 発注の詳細に、進みのタイムラインを出す

`m53-timeline`（base は `main`）。サイクル 09 の計画の `cycle-09-plan-m55` の先端 `7702f10` から切った。計画と M52 の PR が未マージの間は、それらの commit も PR の差分に見える。M53 の差分は `7702f10..` である。

PR #100 の実装レビューは、実装者が 2 系統に同じ依頼で出した。どちらも Go だった。どちらの系統も、`7702f10..d3d4434` の diff を `git show d3d4434:<パス>` で読んだ。

- Claude：作業ツリーが `d3d4434` と同じことを確かめてから、手元で M53 の完了条件の rspec を流した（1424 examples, 0 failures）。壊し方（取消依頼の枝の空の時刻の除外を外す）も流した。画面の検査と E2E は流していない
- Codex：spec を流していない。読み取り専用の環境で rbenv が一時ファイルを作れず、`db:test:prepare` が起動の前に失敗したからである。受け手のコードを手元で評価して、再配送の期待を照らした

Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High 以上の指摘が無いので、読み直しには出していない。

| 系統 | 判定 |
|---|---|
| Codex | Go（Medium 1） |
| Claude | Go（Medium 1・Low 1） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘なし |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R1） | 指摘（R1・R2） |
| 参照の維持 | 指摘なし | 指摘なし |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | R1：受け手の再配送の example は、同じイベントを 2 回渡す。2 回とも同じ `occurred_at` を書くので、空のときだけ書く条件（`unless order.supplier_cancelled_at` など）を外しても通る | `supplier_event_receiver_spec.rb` の「発生の時刻」に、5 つのイベントごとの example を足した。後から 1 時間後の発生の時刻で届けても、先に書いた時刻を書き換えないことを確かめる（`:209`）。4 つの条件を 1 つずつ外すと、それぞれ足した example が落ちる（下の表） | この節を載せた commit |
| Medium | Claude | R1：`timeline_for` の単体に、回答待ちの取消依頼を持つ発注の example が無い。取消依頼の枝の `WHERE events.occurred_at IS NOT NULL` を外しても、rspec の全体が通る | `purchase_orders_spec.rb` に、回答待ちの取消依頼が取消依頼だけを出す example を足した（`:191`）。条件を外すと、この example が `NoMethodError` で落ちる（下の表） | 同上 |
| Low | Claude | R2：E2E は、請求書を発行した発注を「検収済で明細が 2 件」の行で選ぶ。この選び方は、世界の発注の組に頼る | 発注の組を決める側（`lib/demo_world.rb` の `ORDERS` のコメント）に、E2E の選び方の前提と、組を変えるときに E2E も変えることを書いた。受領請求書の画面には発注への手がかり（発注番号・リンク）が無いので、選び方そのものは変えていない | 同上 |

あわせて、Claude の違和感 1 に沿って、進みが読む行の書き方を直した。前は「状況の式と同じ行から組み立てる」と書いていた。状況の式が読むのは発注の時刻列・入荷・検収だけで、取消依頼と受領請求書は式の外にある。そこで「状況の式が読む行に、取消依頼と受領請求書を足した行」と書いた。直した場所は次のとおりである。

- 計画の M53 の目的と、マイルストーンの一覧の行
- `graphql-schema.md`「発注側の視点」
- `showcase.md` のテーマ 4
- `purchase_order_timeline.rb` の冒頭のコメント
- `purchase_orders_spec.rb` の冒頭のコメント

直す前の形を `git grep`（「状況の式と同じ自社の行」「状況と同じ行」「と同じ自社の行」）で数え、証跡の外で 0 件であることを確かめた。

| 壊し方（この節を載せた版） | 結果 |
|---|---|
| 受け手の `accept` から `return if order.accepted_at` を外す | 受注確定の後からの配送の example だけが落ちた（31 examples, 1 failure） |
| 品番照合待ちの `unless order.awaiting_match_at` を外す | 品番照合待ちの同じ example だけが落ちた（31 examples, 1 failure） |
| 受注取消の `unless order.supplier_cancelled_at` を外す | 受注取消の同じ example だけが落ちた（31 examples, 1 failure） |
| `answer_cancellation` から `return if request.outcome` を外す | 承認・却下の同じ example 2 つと、既存の「回答が記録済みの依頼には、後から届いた回答を書かない」（`:113`）が落ちた（31 examples, 3 failures） |
| 取消依頼の枝から `WHERE events.occurred_at IS NOT NULL` を外す | `purchase_orders_spec.rb:191` が、回答待ちの依頼の空の種類の `to_sym` で落ちた（13 examples, 1 failure） |

違和感は次のように扱った。

- Claude 1：「状況の式と同じ行」と書くと、読者は範囲を取り違える → 上のとおり書き方を直した
- Claude 2：請求書の受領の日付は、受注側の発行日（`issued_on`）で、発注側が受け取った日ではない。名前と日付の意味がずれる → IB-146
- Claude 3：`in_time_zone` に引数を渡さず `Time.zone` に従う。計画の文は `config.time_zone` と書く → 扱わない。`Time.zone` は `config.time_zone`（`Asia/Tokyo`）で、コードに `Time.use_zone` は無い。業務の日付を決めるほかの公開 API（`Date.current`）も `Time.zone` に従うので、そろえた
- Codex 1：E2E の選び方が世界の偶然の特徴に頼る → Claude R2 と同じ対応
- Codex 2：出来事の種類と enum の一致の検査が無い → IB-145 にある

### 実装の記録

下の spec の行の番号は、実装レビューに出した `d3d4434` の版のものである。

#### 計画との違い

- 作るもの 2 の読み方：計画は「行は `Scope` の自社の発注に結んで読み、1 回の問い合わせ（`UNION ALL`）で全発注の分を読む」とした。公開 API が `Scope.call(actor, :own).where(id: order_ids)` を 1 回作り、内部のモジュール `Purchasing::PurchaseOrderTimeline`（`packs/purchasing/app/models/purchasing/purchase_order_timeline.rb`。状況の式の `PurchaseOrderStatus` と同じ置き場）が、それを CTE（`scoped_orders`）にして、発注・取消依頼・入荷・検収・受領請求書の 5 つの枝をすべてその CTE に結ぶ。発注の時刻列 4 つと取消依頼の 2 つの時刻は、枝の中で `CROSS JOIN LATERAL (VALUES …)` で出来事の行にする。計画の「`UNION ALL` のどの枝から `Scope` を外しても落ちる」は、その枝だけを `Scope` を通さない CTE に結び替える壊し方で確かめた（下の表）。計画の文は変えていない
- 作るもの 2 の業務の順：計画の表は取消の承認と却下を 1 行に書く。並べ方の順位は、表の並びのとおり承認 → 却下にした（OI-220 の (3)）
- 作るもの 4 の色と見出し：計画の「OI-192 の合計の欄と同じ控えめの色」は、合計の欄の「取消」が色を持たないので、取り消した伝票の明細の文言と同じ `text-muted-foreground` にした。見出しは「進み」にした（OI-220 の (1)・(2)）。取消の出来事の判定を `frontend/lib/format.ts` の `isCancellationEvent` にし、単体（`lib/format.test.ts`）を足した。計画は単体を名指ししていない
- `CancellationRequest.decidedAt` の説明は、計画のとおりに直し、`architecture/graphql-schema.md` の SDL の写しにも同じ説明を足した

#### RED

期待の不一致で落ちたものは次の 3 つである。

1. `supplier_event_receiver_spec.rb` の「発生の時刻」（5 つのイベントの型に `occurred_at` を足し、受け手を直す前の `42d39d6` の作業ツリーで流した）。26 examples, 5 failures。落ちたのは「運んだ発生の時刻を書く」の 5 つで、どれも `expected: 2026-10-14 10:20:30.123456 +0900 got: 2026-10-15 09:00:00 +0900`（受け取った時刻）だった。取消承認は `decided_at` と発注の `cancelled_at` の 2 つが同じ値で落ちた。古いペイロードで受け取った時刻を書く 5 つは、直す前も通る（直す前は常に受け取った時刻を書く）ので、下の壊して落ちる記録で代える
2. 発行元の 5 つの spec（発行元が仮に発行するときの時刻を渡す形で流した）。58 examples, 5 failures。受注の `confirmed_at` を渡す 2 つ（`purchase_order_translator_spec.rb` の受注確定・`part_mappings_spec.rb`）、審査の `decided_at` を渡す 2 つ（`cancellation_reviews_spec.rb` の承認・却下）、受注の `cancelled_at` を渡す 1 つ（`order_cancellation_spec.rb:55`）が、どれもマイクロ秒の違う時刻の文字列で落ちた（例：`-:occurred_at => "…17:38:52.030730+09:00"`・`+:occurred_at => "…17:38:52.031613+09:00"`）。発行するときの時刻が仕様の 2 つ（`purchase_order_translator_spec.rb:78`・`purchasing_event_receiver_spec.rb:66`）は、この形で通るので、壊して落ちる記録で代える
3. `packs/purchasing/spec/public/purchasing/purchase_orders_spec.rb` の `.timeline_for`（公開 API を空の配列を返す形で置いて流した）。12 examples, 6 failures。足した 6 つがすべて、出来事が `got: []`（SQL の数の example は `got: {… => 0, … => 0}`）で落ちた。他社の発注を混ぜる example は、対照の自社の出来事で落ちた

次の spec は、実装の後に書いたか、書いた時点で通ったので、壊して落ちる記録で RED に代える。

- `purchase_orders_spec.rb:178`（同じ時刻の出来事の業務の順）：初めは発注の時刻列どうしを同じ時刻にした example にし、業務の順を外しても落ちなかった（行の ID が同じで、並べ替えの結果がたまたま表の順だった）。行の ID の順（発注が先）が業務の順（却下が先）と逆になる、却下と受注側の取消の組に書き直した（`9a437a0`）
- `supplier_event_receiver_spec.rb:209`（`new` が `occurred_at` を求める）
- `spec/requests/purchase_orders_spec.rb:107`（発注の詳細の `timeline` が型の認可を通り、出荷の時刻が null）
- `spec/matrix/graphql_matrix_spec.rb`（`NESTED_APIS` の `timeline_for` の行）
- `frontend/lib/format.test.ts` の `isCancellationEvent` と、`frontend/e2e/purchase-order-timeline.spec.ts`

#### 壊して落ちる記録

壊す前にファイルを一時の置き場に複製し、複製から戻した。

| 壊し方 | 結果 |
|---|---|
| 受け手の `occurred_at` の読みを `Time.current` に戻す | `supplier_event_receiver_spec.rb` の「運んだ発生の時刻を書く」の 5 つが落ちた（26 examples, 5 failures） |
| 受け手の空のときの `Time.current` を外す（`Time.iso8601(event.occurred_at.to_s)`） | 古いペイロードの 5 つが落ちた（26 examples, 5 failures） |
| `CancellationRejected.from_payload` を消す | 却下の古いペイロードの 1 つが落ちた（26 examples, 1 failure） |
| `PartMatchPending.new` に `occurred_at` の既定の空を持たせる | `supplier_event_receiver_spec.rb:209` が `nothing was raised` で落ちた |
| 自動の却下の `occurred_at` を依頼の時刻（`event.requested_at`）にする | `purchasing_event_receiver_spec.rb:66` だけが落ちた（18 examples, 1 failure） |
| 品番照合待ちの `occurred_at` を発行の 1 秒前にする | `purchase_order_translator_spec.rb:78` だけが落ちた（9 examples, 1 failure） |
| 発注の枝の CTE を、`Scope` を通さない CTE に結び替える | `purchase_orders_spec.rb:235`（他社の発注を混ぜる）だけが、他社の発注の ID に出来事が返って落ちた（12 examples, 1 failure） |
| 同じく取消依頼の枝 | 同上 |
| 同じく入荷の枝 | 同上 |
| 同じく検収の枝 | 同上 |
| 同じく受領請求書の枝 | 同上 |
| 並べ方の時刻の空を前に置く | `:159`・`:214` が落ちた（12 examples, 2 failures） |
| 並べ方から業務の順位を外す | `:159`・`:178` が落ちた（12 examples, 2 failures。`:178` を書き直す前は `:159` だけだった） |
| 受領請求書の `EXISTS` を明細の結びに替える | `:214` だけが、同じ発注の明細 2 行の分の請求書の受領が 2 つ出て落ちた（12 examples, 1 failure） |
| 時刻を日本時間にせず、UTC の日付を取る | `:191`（日本時間の 0〜9 時）だけが落ちた（12 examples, 1 failure） |
| 出来事の値の `owner_tenant_id` を空にする | `spec/requests/purchase_orders_spec.rb:107` が、`timeline` の要素の `FORBIDDEN` で落ちた |
| `timeline_for` の `Scope` を `PurchaseOrder.where(id:)` にする | 入口の行列の `timeline_for` の行が `expected: [:supplier] got: [:supplier, :granted_buyer, :ungranted_buyer, :revoked_buyer, :stranger]` で落ちた |
| `NESTED_APIS` から `timeline_for` の行を消す | 入口の行列の鍵の一致の example が、`the missing elements were: ["Purchasing::PurchaseOrders.timeline_for"]` で落ちた |
| 画面の部品で出来事を逆の順に出す | `purchase-order-timeline.spec.ts` の 2 つが、出来事の種類の配列の不一致で落ちた（2 failed） |
| 取消の出来事に取消依頼を足す | `format.test.ts` の `isCancellationEvent` が落ちた（1 failed・152 passed） |

### 確かめたこと

#### 手元で流したもの

```sh
TEST_DATABASE=factory_ops_m53_test bundle exec rspec packs/purchasing/spec packs/sales/spec packs/fulfillment/spec packs/billing/spec spec/contracts spec/matrix/graphql_matrix_spec.rb spec/graphql spec/requests/purchase_orders_spec.rb   # 0 failures
cd frontend && npm run codegen:check && npm run lint && npm run typecheck && npm run test:unit   # 通った（Node 22、npm ci の後。単体は 153 passed）
cd frontend && E2E_DATABASE=factory_ops_m53_e2e PLAYWRIGHT_CHANNEL=chrome npm run test:e2e -- e2e/purchase-order-timeline.spec.ts   # 2 passed
TEST_DATABASE=factory_ops_m53_test BASE_REF=origin/cycle-09-plan-m55 bin/ci   # e9b8290 で、すべての工程が通った。rspec は 3144 examples, 0 failures
bin/check-open-items --due M53 && bin/check-commit-refs   # 通った
cd frontend && E2E_DATABASE=factory_ops_m53_e2e PLAYWRIGHT_CHANNEL=chrome npm run test:e2e   # e9b8290 で 74 passed・26 skipped（1.9 分）
```

`bin/check-schema-compat` は、足した型と enum とフィールドを非破壊の変更として通した（落とす変更は無い）。分岐の網羅率の警告は、`e9b8290` の `bin/ci`（基準は `7702f10`）で 0 件だった。E2E の全体は、1 分の load average が 10 前後の間に 1 回流した。発注の詳細の寸法とコントラストは、`/buyer/purchase-orders/[id]` を測る既存の E2E（`frontend/e2e/support/screens.ts`）がそのまま測り、通った。

### 残件の処理

引当先が M53 の行（OI-210・OI-212。どちらも `decided`）は、着手の前と PR の前に台帳を読み、作るもの 1〜4 で反映した。IB-139 は計画のとおり M53 で起票済みのまま。画面で計画が書き切らなかった 3 つを OI-220（`judgment`）に、出来事の種類の一覧と enum の一致の検査が無いことを IB-145 に、実装レビューの違和感（請求書の受領の日付の意味）を IB-146 に積んだ。取りまとめ役の判断の受け口（`decisions.md`）は、着手の時と各 commit の前に読み、どの時点でも空だった。
