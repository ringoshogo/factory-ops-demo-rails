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

`bin/check-schema-compat` は、足した型と enum とフィールドを非破壊の変更として通した（落とす変更は無い）。分岐の網羅率の警告は、`e9b8290` と `2bd0288` の `bin/ci`（基準は `7702f10`）でどちらも 0 件で、PR の CI の test のジョブの注釈も、どちらの先端でも 0 件だった。実装レビューの直しの後の `2bd0288` でも `TEST_DATABASE=factory_ops_m53_test BASE_REF=origin/cycle-09-plan-m55 bin/ci` が通った（3150 examples, 0 failures）。直しは spec・文書・コメントだけで、手元の E2E は流し直していない。

PR #100 の CI は、push のたびに `pull_request` で流れ、どれも通った（`publish` は `pull_request` なので skip）。流し直しはしていない。

| 先端 | 実行 | 結果 |
|---|---|---|
| `d3d4434` | [38877978187](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38877978187) | success（e2e 3 分 38 秒・test 6 分 34 秒） |
| `2bd0288` | [38879904483](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38879904483) | success（e2e 3 分 49 秒・test 4 分 18 秒） |

この表を載せた commit は証跡と `handoff.md` の件数だけを変える。その CI の結果は PR の checks で見る。E2E の全体は、1 分の load average が 10 前後の間に 1 回流した。発注の詳細の寸法とコントラストは、`/buyer/purchase-orders/[id]` を測る既存の E2E（`frontend/e2e/support/screens.ts`）がそのまま測り、通った。

### 残件の処理

引当先が M53 の行（OI-210・OI-212。どちらも `decided`）は、着手の前と PR の前に台帳を読み、作るもの 1〜4 で反映した。IB-139 は計画のとおり M53 で起票済みのまま。画面で計画が書き切らなかった 3 つを OI-220（`judgment`）に、出来事の種類の一覧と enum の一致の検査が無いことを IB-145 に、実装レビューの違和感（請求書の受領の日付の意味）を IB-146 に積んだ。取りまとめ役の判断の受け口（`decisions.md`）は、着手の時と各 commit の前と報告の前に読み、どの時点でも空だった。

## M54 同じテナントの中の受注と出荷・請求を、同期の呼び出しでつなぐ

`m54-same-tenant-sync`（base は `main`）。M53 の先端 `fe9abd1`（`origin/m53-timeline`）から切った。計画と M52・M53 の PR が未マージの間は、それらの commit も PR の差分に見える。M54 の差分は `fe9abd1..` である。

PR #101 の実装レビューは、実装者が 2 系統に同じ依頼で出した。どちらも Go だった。どちらの系統も、`32ebd8e` を展開したディレクトリと `fe9abd1..32ebd8e` の diff だけを読んだ。

- Claude：spec を流さず、コードと spec を読んで、壊したときに何が落ちるかを確かめた。消えた example の名前（47 件）を対応の表と照らした
- Codex：`--skip-git-repo-check` を付け、読み取り専用で流した。検査と壊し方は流し直していない

Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High 以上の指摘が無いので、読み直しには出していない。

| 系統 | 判定 |
|---|---|
| Codex | Go（Medium 3・Low 1） |
| Claude | Go（Medium 2・Low 4） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R1） | 指摘（R1） |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R2） | 指摘（R2・R3） |
| 参照の維持 | 指摘（R3・R4） | 指摘（R4・R5・R6） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium・Low | Claude R1・Codex R1 | 計画の「文書に残すこと」の `git grep` が、ADR 012 の「状態」の表の名前（`shipping_holds`）で 1 件当たり、0 件にならない。grep の結果も証跡に無い | ADR 012 の文から表と列の名前を外した。grep が 0 件であることを、この節の「手元で流したもの」に書いた | この節を載せた commit |
| Medium | Claude R2 | 状況の式の `COALESCE` を外しても落ちない。効くのは出荷指示の読み込みと出荷予定日の `NOT` だけで、受注の見えない出荷依頼の example が無い | `shipment_requests_spec.rb:140` に、受注の見えない出荷依頼の有効な指示を読み込みが返し、出荷予定日の位置に並べる example を足した。`COALESCE` を外すとこれだけが落ちる（下の表） | 同上 |
| Medium | Codex R2 | `Instructions.create` のロックの順（受注 → 出荷依頼）を確かめる example が無い。出荷依頼を先にロックしても競合テストは落ちない | `instructions_spec.rb:106` に、`FOR UPDATE` の順が受注 → 出荷依頼であることを確かめる example を足した。出荷依頼を先にロックするとこれだけが落ちる | 同上 |
| Low | Claude R3 | `cancel_vs_ship_spec.rb` の待つ先の補助のコメントが、出荷依頼と受注の順の誤りを捕まえると読める | コメントを、計上が受注の行をロックしない形を捕まえ、順はロックの順の example が確かめる、と直した | 同上 |
| Medium | Codex R4 | 「出荷は受注の行を書き換えないので」が、計上が受注を出荷済にする実装と食い違う。出荷指示を残す理由として依存の向きが逆 | `data-model.md` の 2 か所、ADR 012 決定 3、計画の M54 の作るもの 3、`shipment_requests_spec.rb` のコメントを、状況は「いまの受注の行から読む」、指示を残すのは「受注は出荷に依存しないので、受注の取消は出荷指示を書き換えない」に直した。直す前の言い方を `git grep` で数え、0 件にした | 同上 |
| Low | Claude R4 | `spec/requests/cancellations_spec.rb` の冒頭のコメントと 2 つの example の名前が、出荷停止の解除と出荷指示の取消を前提にしている | 審査の決着と、出荷依頼が取消済になって出荷指示を返さない形に直した | 同上 |
| Low | Claude R5 | `mark_shipped` の失敗の `path: [:sales_order_id]` を、入力に受注 ID の無い `postShipment` がそのまま返す | `Shipping.post` が、利用者の渡した出荷依頼 ID を指す `NOT_FOUND` に写す。`shipping_spec.rb:121` の期待も直した。写さずに返すとこれが落ちる | 同上 |
| Low | Claude R6 | マイグレーションの `down` を流した記録が無い | 実装の途中で、テストの DB で `db:rollback` と `db:migrate` を流し、`down` の後の `structure.sql` が、列の順（`shipment_requests.cancelled_at` が表の最後に付く）を除いて `fe9abd1` と同じになり、もう一度 `up` すると変更の後の形に戻ることを確かめていた。表の説明の `change_table_comment` を足した後も、同じ往復を流した | 記録のみ |
| Medium | Codex R3 | 終えたマイルストーンの計画の節（M14・M21〜M24・M26・M40 など）に、消したイベントと出荷停止の表を前提にした文が残る | 直さない。終えたマイルストーンの節は、そのマイルストーンが作ったものの記録として書き換えず、いまの形は設計文書と ADR 012 が正本である。判断を OI-223（`judgment`）に積んだ | — |

| 壊し方（この節を載せた版） | 結果 |
|---|---|
| 状況の式の `order_flag` から `COALESCE` を外す | `shipment_requests_spec.rb:140` だけが落ちた（`packs/fulfillment/spec` の 70 examples, 1 failure） |
| `Instructions.create` で出荷依頼を受注より先にロックする | `instructions_spec.rb:106` だけが落ちた（13 examples, 1 failure） |
| `Shipping.post` で `mark_shipped` の失敗を写さずに返す | `shipping_spec.rb:121` だけが落ちた（14 examples, 1 failure） |

違和感は次のように扱った。

- Codex 1：出荷依頼の受注番号の写しの「写しを作った時点では」が、コメントの規約の「経緯を書かない」と緊張する → IB-148
- Claude 1：`testing.md` の `INSERT ... ON CONFLICT DO UPDATE` の段落が、例を消した後に当たる入口の無い規則として残る → いまは当たる入口が無く、足す人がこの形にする、と 1 文を足した
- Claude 2：計画は、待つ先の確かめで出荷依頼と受注の順の誤りも捕まえる前提で書いていた。待ち終えた接続はタプルのロックを手放すので捕まえない → IB-149。順は Codex R2 で足したロックの順の example と `shipping_spec.rb` のロックの順の example が確かめる
- Claude 3：`shipping_lock_spec.rb:116` は、自動の却下の「取消却下」が出たことを見ていない → 扱わない。自動の却下のイベントは単体の `purchasing_event_receiver_spec.rb:53` が確かめ、競合テストは未決の審査を残さないことを確かめる

### 実装の記録

下の spec の行の番号は、実装レビューに出す版のものである。

#### 計画との違い

- 作るもの 2 の `lock`：計画は「取消済・審査中・出荷済の 3 つを返す」としたが、取消済と審査中の 2 つだけを返す（`Sales::OrderShipping::State`）。出荷は自分の出荷実績で出荷済を読み、受注の出荷済は計上が同じトランザクションで書くので、読む箇所が無い。計画の作るもの 2 の文を `de09118` で直した（OI-222 の (1)）
- 作るもの 4 の `confirm` の引数：計画は引数を名指ししていない。明細ごとにキーワード引数（得意先・出荷実績 ID・受注明細 ID・発注明細 ID・品目名・単価・数量・税率・検収日）を取る（OI-222 の (2)）
- 作るもの 5 のマイグレーション：計画の表と列を消すほかに、請求対象明細の表の説明の「「請求対象確定」の写し」を、同じマイグレーションの `change_table_comment` で「受注が検収で確定した明細」に直した。消すイベントの名前が表の説明に残るからである（OI-222 の (3)）
- 作るもの 6 の `lock_sites_spec.rb`：計画は `Fulfillment::Instructions.create` の理由を書き直して `shipping_lock_spec.rb` を指すとしたが、競合テストを書いたので、理由ではなく `spec:` の行にした（`mentions: %w[Instructions.create PurchasingEventReceiver.handle]`）。足した `Sales::OrderShipping.lock` の行も同じ spec を指す
- 競合テストの補助：待つ先の表を読む補助を `waiting_row_tables`（`spec/support/concurrency.rb`）とし、表の名前の配列を返す。ガードの example（`spec/concurrency/concurrency_helpers_spec.rb:32`）を足し、`guides/testing.md`「競合テスト」の手順 3 に使い方を書いた（OI-222 の (4)）
- 作るもの 8（OI-208）：取りまとめ役の指示で M54 では作らず、新しい M56 の節に移した。#85 の merge commit がこのブランチの祖先に無く、M55 も M54 から切るので書けないからである。移し先は取りまとめ役の指示どおりサイクル 09 の終わり（main から切るので #85 を祖先に持つ）で、台帳の検査（`bin/check-open-items`）が引当先にマイルストーンの番号と計画の節しか受け付けないので、M56 の節として置き、サイクル末の担当が行う形にした（OI-221）。計画の M54 の作るもの 8 と実装する文書の節と前提の表の文を、M56 の節と M52 の作るもの 3 と `guides/dev-cycle.md` のサイクル 09 の行と `handoff.md`「次にやること」に移した（`de09118`）

#### RED

期待の不一致で落ちたものは、計画が名指しした最初に落とす 4 つの spec である。出荷依頼の factory を受注の行を作る形に変え、4 つの spec に example を足した作業ツリーを、実装の前の `fe9abd1` のコードで流した。63 examples, 10 failures で、どれも期待の不一致だった。

| spec | 落ちた example | 落ち方 |
|---|---|---|
| `shipment_request_status_spec.rb` の「受注の取消と審査」 | 受注を取り消した直後の取消済・未決の審査の出荷停止中と却下で戻ること・承認の後の取消済の 3 つ | `expected: :cancelled got: :instructed`、`expected: :on_hold got: :instructed`、`expected: :cancelled got: :ready` |
| `shipping_spec.rb` | 計上の直後に受注が出荷済になる。取消済と審査中の受注の出荷依頼の計上が `CONFLICT` になる 2 つ | `expected: :shipped got: :allocated`、`expected: [:conflict] got: []` |
| `instructions_spec.rb` | 取消済と審査中の受注の出荷依頼の出荷指示の作成が `CONFLICT` になる 2 つ | `expected: [:conflict] got: []` |
| `shipment_requests_spec.rb` | 取消済の受注の出荷依頼に残った出荷指示を、読み込みが返さず、出荷予定日で予定日の無い出荷依頼と同じ位置に並べる | 返った指示が 2 件（取消済の受注の分を含む）で、ハッシュの不一致 |
| `purchasing_event_receiver_spec.rb` | 検収完了を受けた直後に未請求の請求対象明細ができている | `got: []` |

次の spec は、新しい公開 API を呼ぶので実装の前は読み込みの失敗（`NameError`・`NoMethodError`）でしか落ちないか、実装の後に書いたので、壊して落ちる記録で RED に代える。

- `packs/sales/spec/public/sales/order_shipping_spec.rb`（新しい公開 API の単体）
- `packs/billing/spec/public/billing/billable_items_spec.rb` の `.confirm`
- `shipping_spec.rb` の受注の行の無い出荷依頼の `NOT_FOUND`・`mark_shipped` の失敗で戻す・審査を却下すると計上できる、`instructions_spec.rb` の受注の行の無い出荷依頼の `NOT_FOUND`・審査の却下と決着した審査・取消済の受注の出荷依頼の指示の取消
- `shipment_request_status_spec.rb` の RLS を開いた example（他社の受注の取消と審査）
- `fulfillment/sales_event_receiver_spec.rb` の取消の後に届いた「出荷可能」
- 競合テスト：`spec/concurrency/cancel_vs_ship_spec.rb`・`shipping_lock_spec.rb` の「取消の審査」・`concurrency_helpers_spec.rb:32`

#### 出荷依頼の factory を変えた後に落ちた spec

`:shipment_request` を同じテナントの受注の行（`:sales_order`）を作る形に変えた後、実装の前のコードで、計画が名指しした spec を流した（`packs/fulfillment/spec/concurrency`・`post_shipment_audit_spec.rb`・`supplier_shipments_spec.rb`・`audit_spec.rb`・`spec/matrix`）。1573 examples, 5 failures で、落ちたのはトランザクションを使わない競合テストの 5 つ（`shipping_lock_spec.rb` の 4 つと `post_shipment_audit_spec.rb`）だけだった。どれも後始末が「sales_orders に行が残った。delete_owned_rows に渡す表を足す」で落ちた。後始末の表に `sales_orders`（`shipping_lock_spec.rb` は審査も作るので `cancellation_reviews` も）を足して直した。入口の行列の世界は、出荷の表の行の数だけ受注の行が増え、期待を変えずに通った。

逆に、実装の後に factory を受注の行を作らない形（`SecureRandom.uuid`）に戻すと、計上と出荷指示の作成が `NOT_FOUND` になり、`packs/fulfillment/spec`・`post_shipment_audit_spec.rb`・`audit_spec.rb`・入口の行列の 789 examples のうち 38 が落ちた（入口の行列は `Mutation.createShippingInstruction`・`Mutation.postShipment` の受注側の行）。

#### 壊して落ちる記録

壊す前にファイルを一時の置き場に複製し、複製から戻した。

| 壊し方 | 結果 |
|---|---|
| 状況の式から取消済を外す（`.when(false)`） | `shipment_request_status_spec.rb` の導出表・受注の取消・承認の example、`instructions_spec.rb:84`、`sales_event_receiver_spec.rb:64`、`shipment_requests_spec.rb` の 2 つが落ちた（59 examples, 9 failures） |
| 状況の式から審査中を外す | `shipment_request_status_spec.rb` の導出表・決着した審査・審査の範囲・未決の審査の example、`instructions_spec.rb:61`、`shipment_requests_spec.rb:30` が落ちた（59 examples, 7 failures） |
| `Shipping.post` から `mark_shipped` を外す | `shipping_spec.rb:71`（計上の直後の出荷済）・`:121`、`cancel_vs_ship_spec.rb:86`（計上が先なら取消は出荷済を読んで `CONFLICT`）が落ちた（53 examples, 3 failures） |
| `Shipping.post` から `mark_shipped` の失敗で戻すことを外す | `shipping_spec.rb:121` だけが落ちた（14 examples, 1 failure） |
| `Instructions.create` から受注のロックを外す（`FOR UPDATE` なしで読む） | `shipping_lock_spec.rb:146`・`:158`（審査の作成と出荷指示の作成の両方の順）が落ちた（8 examples, 2 failures） |
| `Shipping.post` から受注のロックを外す | `shipping_lock_spec.rb:103`（審査の作成が先）・`:129`（却下が先）、`cancel_vs_ship_spec.rb:74`・`:108`（取消と承認が先）が落ちた（12 examples, 4 failures） |
| `Sales::OrderShipping.lock` から `FOR UPDATE` を外す | 上の 2 つを合わせた 6 つが落ちた（12 examples, 6 failures） |
| `Shipping.post` で出荷依頼を受注より先にロックする | `shipping_spec.rb:147`（ロックの順）だけが落ちた（18 examples, 1 failure）。待つ先の表の確かめは落ちない。取消が先のとき、計上は出荷依頼の行ロックを得てから受注の行を待つので、待つ先は受注の行のままだからである |
| `status_sql` から `Scope` を外す | `order_shipping_spec.rb:100`・`shipment_request_status_spec.rb:136`（RLS を開いて他社の受注の取消と審査）が落ちた（17 examples, 2 failures） |
| `lock` から `Scope` を外す | `order_shipping_spec.rb:85` だけが落ちた（7 examples, 1 failure） |
| `mark_shipped` から `Scope` を外す | 同上 |
| `mark_shipped` から出荷済の時刻が空のときだけ書く条件を外す | `order_shipping_spec.rb:43` だけが落ちた（7 examples, 1 failure） |
| `lock` の審査中を常に偽にする | `order_shipping_spec.rb:21`、`instructions_spec.rb:61`、`shipping_spec.rb:98` など 5 つが落ちた（56 examples, 5 failures） |
| `Instructions.create` で受注の見えない出荷依頼も続ける | `instructions_spec.rb:94` だけが落ちた（12 examples, 1 failure） |
| `Shipping.post` で受注の見えない出荷依頼も続ける | `shipping_spec.rb:108` だけが落ちた（14 examples, 1 failure） |
| `instructions_for` から取消済の除外を外す | `shipment_requests_spec.rb:123` だけが、指示の読み込みの期待で落ちた（12 examples, 1 failure） |
| `planned_date` から取消済の除外を外す | `shipment_requests_spec.rb:123` だけが、出荷予定日で並べた期待で落ちた（12 examples, 1 failure） |
| `confirm` の `insert` を `insert!` にする（重複を飛ばさない） | `billable_items_spec.rb` の 4 つと、`purchasing_event_receiver_spec.rb` の検収完了の 9 つが落ちた（26 examples, 13 failures） |
| 検収完了の受け手から `confirm` の呼び出しを外す | `purchasing_event_receiver_spec.rb:227`・`:244`・`:252` が落ちた（19 examples, 3 failures） |
| 検収数量が 0 の明細も `confirm` する | `:252`（数量 0）を含む 7 つが、請求対象明細の数量の CHECK 制約で落ちた（19 examples, 7 failures） |
| `waiting_row_tables` が常に `sales_orders` を返す | `concurrency_helpers_spec.rb:32` が落ちた（10 examples, 1 failure） |
| `waiting_row_tables` がタプルのロックで絞らない | `concurrency_helpers_spec.rb:32` と `cancel_vs_ship_spec.rb` の待つ先を確かめる 3 つが落ちた（14 examples, 4 failures） |

落ちなかったもの：`confirm` から `Tenancy.require_tenant!` を外しても、`TenantRecord` の `default_scope` が同じ `MissingTenant` を SQL を流す前に上げるので、`billable_items_spec.rb` のテナントの設定の外の example は落ちない（7 examples, 0 failures）。IB-59（見送り）と同じ形である。

#### 消した spec と example の性質の対応

`git grep` で、消したイベントと受け手を名指しする spec を数え、同期の形の期待に書き換えるか、消した受け手だけを確かめる spec を消した。消した example の `expect` が確かめていた性質と、移し先は次のとおりである（`guides/testing.md`「層への配分」）。

| 消した spec・example | 確かめていた性質 | 移し先 |
|---|---|---|
| `packs/sales/spec/public/sales/fulfillment_event_receiver_spec.rb`（ファイル） | 受注の `shipped_at` を 1 回だけ書く | `order_shipping_spec.rb:43`・`shipping_spec.rb:71` |
| 同上 | 他社の受注を RLS を開いても書かない | `order_shipping_spec.rb:85` |
| 同上 | 発注側テナントが一致しない受注は書かない・配送表に無いイベントは失敗する | 対応先なし。`mark_shipped` は出荷依頼が持つ自社の受注の ID だけを受け取り、受け手は消した |
| `packs/billing/spec/public/billing/sales_event_receiver_spec.rb`（ファイル） | 受注側の名義で未請求の明細を書く・同じ出荷実績の別の明細は別の行・請求済みの明細を作り直さない・重複して 1 回分 | `billable_items_spec.rb` の `.confirm` の 4 つと、`purchasing_event_receiver_spec.rb` の冪等な受け手と再配送の example |
| 同上 | 配送表に無いイベントは失敗する | 対応先なし（受け手を消した） |
| `packs/fulfillment/spec/concurrency/fulfillment/shipping_hold_lock_spec.rb`（ファイル） | 出荷依頼がまだ無い受注への停止と「出荷可能」が並んでも、停止中の受注に有効な出荷指示が残らない | `shipping_lock_spec.rb:146`（審査が先なら出荷指示の作成は `CONFLICT`）と、`shipment_request_status_spec.rb` の未決の審査の example（審査を出荷依頼より先に作る） |
| `fulfillment/sales_event_receiver_spec.rb` の「出荷停止と出荷取消」（17 examples） | 停止で出荷停止中・解除で戻る・取消で取消済と指示の取消・審査を経ない取消 | `shipment_request_status_spec.rb` の「受注の取消と審査」、`instructions_spec.rb:84`、`shipment_requests_spec.rb:123` |
| 同上 | 停止・解除・取消の冪等と、他社の同じ審査 ID・他社の受注の行を書かない | 対応先なし。書く行が無くなった。他社の受注を読まないことは `order_shipping_spec.rb:100`・`shipment_request_status_spec.rb:136` |
| 同上の「届く順の入れ替わり」（5 examples） | 停止・解除・取消・出荷可能の順が入れ替わっても取り残さない | 同期にしたので、残る入れ替わりは「出荷可能」が取消の後に届くことだけで、`fulfillment/sales_event_receiver_spec.rb:64` |
| `shipment_request_status_spec.rb` の他社の出荷停止の example | 他社の名義の行が状況に入らない | 同じファイルの `:136`（他社の受注を指す出荷依頼） |
| `instructions_spec.rb` の「出荷停止」（2 examples）、`shipping_spec.rb` の解除の example | 停止中は作成と計上が `CONFLICT`、解除すると通る、別の受注と解除した停止は止めない | `instructions_spec.rb:61`・`:76`、`shipping_spec.rb` の「受注の取消と審査」 |
| `shipping_lock_spec.rb` の停止の受け手の example | 停止の受け手のコミットまで計上が待ち `CONFLICT` | `shipping_lock_spec.rb:103` |
| `cancel_vs_ship_spec.rb` の「審査の承認」の計上が先の example | 審査の経路でも計上が先なら取消は `CONFLICT` | 審査の行がそのまま停止になるので作れない（計画のとおり）。計上が先の取消の `CONFLICT` は受注側の取消の `:86` が同じ内部の取消の処理で確かめる |
| `purchasing_event_receiver_spec.rb` の `NotShippedYet` の example | 出荷済でない受注の検収は何も書かずに失敗 | 同じ example を CHECK 制約の失敗の期待に書き換えた（`:259`） |
| `cancellation_reviews_spec.rb`・`order_cancellation_spec.rb` の「出荷取消は出荷可能を出していないことを運ぶ」（3 examples） | 取消の前の引当の状態を読む | 対応先なし（読みを消した）。全量を引き当てていない受注と品番照合待ちの受注を取り消せることは、同じ example を書き換えて残した |
| `spec/contracts/shipment_posted_delivery_spec.rb` の受注の宛先 | 受注の受け手に 1 件登録され、重複しても 1 回分 | 宛先が購買だけになったことを同じ spec で確かめる。受注の出荷済は `shipping_spec.rb:71` |

rspec の件数は、M53 の 3150 から 3117 になり、実装レビューの直しで 3119 になった。

### 確かめたこと

#### 手元で流したもの

```sh
TEST_DATABASE=factory_ops_m54_test bundle exec rspec packs/fulfillment/spec packs/sales/spec packs/billing/spec spec/concurrency spec/contracts spec/scenarios spec/db spec/matrix   # 0 failures
TEST_DATABASE=factory_ops_m54_test BASE_REF=origin/m53-timeline bin/ci   # de09118 で、すべての工程が通った。rspec は 3117 examples, 0 failures
bin/check-open-items --due M54 && bin/check-commit-refs   # 通った
git grep -n -e ShippingHeld -e ShippingHoldReleased -e ShipmentCancelled -e BillableItemConfirmed -e shipping_holds -e ShippingHold -e NotShippedYet -e FulfillmentEventReceiver -e Billing::SalesEventReceiver -e release_hold -e lock_sales_order -e 'held?' -e 'ready_for_shipment:' -e '\.ready_for_shipment' -- . ':!docs/plans' ':!docs/implementation-plan.md' ':!db/migrate'   # 実装レビューの直しの後に 0 件
cd frontend && npm run codegen:check && npm run lint && npm run typecheck   # 通った（Node 22、npm ci の後）
cd frontend && E2E_DATABASE=factory_ops_m54_e2e PLAYWRIGHT_CHANNEL=chrome npm run test:e2e   # e4ffc00 で 74 passed・26 skipped（1.7 分）
```

`bin/packwerk validate` は、足した 2 つの依存（`fulfillment` → `sales`、`sales` → `billing`）で循環を出さずに通った。分岐の網羅率の警告は、`de09118` の `bin/ci`（基準は `fe9abd1`）で 0 件だった。`e4ffc00` は出荷計上の型のコメントと spec の説明だけを変え、`bin/rubocop` と台帳の検査を流し直した。E2E は、取消・審査中・出荷の画面の状況の表示を含めて期待を変えずに通った（`DemoWorld` はテナントをまたぐイベントのために `drain` を残している）。

実装の途中で、マイグレーションの後に `shipping_holds` を後始末の表に持つ古い競合テストが後始末に失敗し、テストの DB に行とジョブが残って、`allocation_spec.rb` と受け手の spec が残った行で落ちた。テストの DB を作り直してから流し直し、通った。製品の不具合ではない。

実装レビューの直しの後も `TEST_DATABASE=factory_ops_m54_test BASE_REF=origin/m53-timeline bin/ci` が通った（3119 examples, 0 failures、分岐の網羅率の警告 0 件）。直しは spec・文書・コメントと `Shipping.post` の失敗の写しだけで、手元の E2E は流し直していない。

PR #101 の CI は、push のたびに `pull_request` で流れた（`publish` は `pull_request` なので skip）。流し直しはしていない。

| 先端 | 実行 | 結果 |
|---|---|---|
| `e4ffc00` | [38887125143](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38887125143) | success |
| `32ebd8e` | [38887230016](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38887230016) | success（e2e 3 分 24 秒・test 6 分 5 秒） |
| `d212b8d` | [38889458244](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38889458244) | success（e2e 3 分 18 秒・test 5 分 24 秒） |

この表を載せた commit は証跡だけを変える。その CI の結果は PR の checks で見る。

### 残件の処理

引当先が M54 の行（OI-211・OI-213。どちらも `decided`）は、着手の前と PR の前に台帳を読み、作るもの 1〜7 で反映した。OI-208 は、取りまとめ役の指示で引当先を M56 に移した（内容の欄に指示を書いた。状態が `open` の行は結果の欄に書けないので、検査に合わせて内容の欄にした）。移し先の形の判断を OI-221、計画が書き切らなかった 4 つを OI-222 に `judgment` で積み、出荷依頼の受注番号の写しを受注の副問い合わせに替える候補を IB-147 に積んだ。IB-140 は計画のとおり起票済みのまま。取りまとめ役の判断の受け口（`decisions.md`）は、着手の時と各 commit の前と報告の前に読み、どの時点でも空だった。

## M55 責務と関心の分離の崩れを直す：公開 API の戻り値、在庫の不変条件、層ごとの責務

`m55-separation`（base は `main`）。M54 の先端 `42d5416`（`origin/m54-same-tenant-sync`）から切った。計画と M52〜M54 の PR（#98〜#101）が未マージの間は、それらの commit も PR の差分に見える。M55 の差分は `42d5416..` である。

PR #102 の実装レビューは、実装者が 2 系統に同じ依頼で出した。Codex は Conditional Go、Claude は Go だった。どちらの系統も、`c4acc2d` を展開したディレクトリと `42d5416..c4acc2d` の diff だけを読んだ。

- Claude：手元で完了条件の rspec を流し（2815 examples, 0 failures）、ガードの取り付けを外す壊し方と、`Violation` を `StandardError` から継ぐ壊し方を流した。`TracePoint` の例外の伝わり方を Ruby 3.4.11 の小さなスクリプトで確かめ、zeitwerk と rspec-mocks の引用を原文で確かめた
- Codex：`--skip-git-repo-check` を付け、読み取り専用で流した。spec は流さず、`hold_open` の本体を写した DB の要らない縮小の実験で、子のスレッドのガードの例外で親が待ち続けることを確かめた（実験の Ruby は 2.6.10）

Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High は Codex R1 の 1 件で、直し方が補助の `rescue` を広げて回帰の example を足すと名指しされた Conditional Go なので、直したことをここに書き、読み直しには出していない。

| 系統 | 判定 |
|---|---|
| Codex | Conditional Go（High 1・Medium 2） |
| Claude | Go（Low 4） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R1） | 指摘なし |
| 正しさ | 指摘（R1） | 指摘（R4） |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R1・R2・R3） | 指摘（R1・R2） |
| 参照の維持 | 指摘なし | 指摘（R3・R4） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex R1 | ガードの `Violation` は `Exception` から継ぐので、競合テストの補助 `hold_open` の `rescue StandardError` を通らず、子のスレッドで違反が起きると親が `ready` を待ち続ける | `spec/support/concurrency.rb` の `hold_open`・`in_thread`・後始末の `rescue` を `Exception` に広げ、理由をコメントに書いた。`concurrency_helpers_spec.rb:16` に、子のブロックが `Violation` を出すと、親が上限の時間の内に同じ例外を送出する example を足した。`hold_open` を `StandardError` に戻すとこれが落ちる（下の表） | この節を載せた commit |
| Low | Claude R1 | `Violation` を `Exception` から継ぐ決め（OI-224 の (1)）を、どの example も確かめない | `public_api_returns_spec.rb:113` に、呼ぶ側の `rescue StandardError` の中で違反が起きても外へ出る example を足した。`StandardError` から継ぐとこれだけが落ちる | 同上 |
| Medium・Low | Codex R2・Claude R2 | `entry_callers_spec.rb` の (iii) が `class << self` の中の `def` を数えない。ガードの spec と数え方が違う | `Collector` に `class << self` の中の `def` と `private` の後の非公開を足し、(iii) の負例に、`class << self` の中で直に呼ぶ形と非公開の補助を通す形を足した。数えないように戻すと負例が落ちる | 同上 |
| Medium | Codex R3 | ダッシュボードの安全在庫の上限の仕様の値 100 を、どの example も確かめない（単体は `limit:` に 2・3、request spec は定数を差し替える） | `dashboard_spec.rb:120` に、定数を差し替えずに上限ちょうどの 100 件と 101 件の example を足した。`STOCKS_LIMIT` を 99 にしても 101 にしてもこれが落ちる | 同上 |
| Low | Claude R3 | 「層ごとの責務」の受け手の行が、同じテナントの中を同期でつなぐ規則も spec が守ると読める | 守る仕組みの列を、`EventJob` からだけ呼ばれることは `entry_callers_spec.rb` が落とし、同期と非同期の分け方は機械では落とさず計画レビューと実装レビューが見る、と書き分けた | 同上 |
| Low | Claude R4 | 「コードが引けて写しの無い品目は起きない」が、写しの表を足した後の作り直しの前の既存の DB と食い違い、そのとき在庫の取り込みの行の誤りの文が空になる | 取り込みのコメントと `data-model.md` の取り込みの手順 3 を、作り直しまでは写しが無く在庫数の設定が `NOT_FOUND` で拒む、と直した。`deploy/README.md` の写しの無い間の影響に、在庫の調整と在庫の CSV の行が拒まれることを足した。写しの無い品目の `NOT_FOUND` に文を持たせ、`adjustment_spec.rb` で確かめる。文を外すとそれが落ちる | 同上 |

| 壊し方（この節を載せた版） | 結果 |
|---|---|
| `hold_open` が `StandardError` だけを拾う | `concurrency_helpers_spec.rb:16` だけが落ちた（11 examples, 1 failure） |
| `Violation` を `StandardError` から継ぐ | `public_api_returns_spec.rb:113` だけが落ちた（6 examples, 1 failure） |
| `entry_callers_spec.rb` が `class << self` の中の `def` を数えない | `entry_callers_spec.rb:264`（(iii) の負例）だけが落ちた（6 examples, 1 failure） |
| `STOCKS_LIMIT` を 99 にする・101 にする | どちらも `dashboard_spec.rb:120` だけが落ちた（8 examples, 1 failure） |
| 写しの無い品目の `NOT_FOUND` から文を外す | `adjustment_spec.rb` の写しの確かめの 2 つが落ちた（10 examples, 2 failures） |

違和感は次のように扱った。

- Claude 1：`DemoWorld::Operations` の spec の期待が、実装と同じ式で `find_target` の有無を読む → 期待を mutation の基底クラスの判定（`Mutations::BaseMutation#targeted?`）から読む形に直した
- Claude 2：`lib/` が「各コンテキストの公開 API だけを使う」と書くが、`DemoWorld::Operations` は mutation の宣言を読む → `context-map.md` の `lib/` の行に、規則は同じルートパッケージの mutation の宣言から読むと足した
- Claude 3：`entry_callers_spec.rb` が `packs/*/lib` を読まない → 読む置き場に足した
- Claude 4：上限の仕様の値 100 を確かめない → Codex R3 と同じで、上で直した
- Claude 5：ガードの例外は確かめるメソッドが戻る時点で出るので、違反した呼び出しの書き込みは example のトランザクションが巻き戻すまで残る → 扱わない。テストのガードとして、違反した example が落ちれば足りる
- Codex：未呼び出しの公開 API を失敗にしない制約 → IB-150 に積んである

### 実装の記録

下の spec の行の番号は、実装レビューに出す版のものである。

#### 計画との違い

- 前提にした M54 の結果は、実物と合っていた。ADR 012（同じテナントの中は同期、「出荷可能」だけがイベント）、`Billing::BillableItems.confirm` の呼ぶ側が `Sales::PurchasingEventReceiver` であること、消えた受け手（`Sales::FulfillmentEventReceiver`・`Billing::SalesEventReceiver`）が配送表に無いことを、着手の時に読んで確かめた。操作者のいない公開 API は、計画レビューの調べのとおり 16 個（受け手の `handle` を除く）だった
- 作るもの 1 のガードの例外 `PublicApiReturns::Violation` は `Exception` から継ぐ。計画は例外の種類を名指ししていない。呼ぶ側の `rescue StandardError`（ジョブの `retry_on` など）に拾われると違反が黙って消えるので、RSpec の期待の失敗と同じ形にした（OI-224 の (1)）
- 作るもの 1 のガードを入れた後の全件で、`packs/platform/spec/models/page_spec.rb` の 3 つの example が、`Page.of` のブロックで行のモデルをそのまま返していたためにガードの例外で落ちた。ブロックを ID に写す形に直した（下の「ガードと写しで落ちた spec」）。計画はこの spec を名指ししていない
- 作るもの 1 の (i) の静的な集め方は、計画のとおり Prism で `def self.` と `class << self` の中の `def` を数え、`private_class_method` と `class << self` の中の `private` の後を除く。確かめない種類は、ガードの実装（`PublicApiReturns.unchecked?`）からではなく、spec が計画の一覧（`Data`・イベントの型・policy・ジョブ・例外）から自分で決める。ガードの側から集めると、ガードの抜けを spec が写し取るからである（`guides/dev-cycle.md`「テストから書く」）
- 作るもの 3 の E の表の形：計画は列を名指ししていない。「公開 API」「呼んでよい場所」「テナント」（`決まる前` か `求める`）の 3 列にし、場所は ` で囲んだファイルのパスか定数を「、」で並べ、定数はその中の入れ子も含めた（OI-224 の (2)）。表の行の理由（テナントが決まる前の 3 つ、`own_users` を通す 5 つ、写しの 4 つ、`confirm`）は、表の下の箇条に移し、散文の列挙を消した
- 作るもの 3 の F：計画の「対応が食い違うときは例外にする」を、`DemoWorld::Operations::Mismatch` にした。規則を評価する前に、操作の対象の有無と mutation の `find_target` の有無を比べる。食い違いの例外を外しても計画の example は落ちないので、`demo_world_spec.rb` の同じ example に、対象の有無を食い違えて呼ぶと `Mismatch` になることと、食い違わなければ通る対照を足した（OI-224 の (3)）
- 作るもの 3 の H：`verify!` の前に送信先を別の値にする手段は、`Provider` の `@current` を spec から直に書く形にした。送信先を差し替える公開のメソッドは無く、足すと本番のコードに試験のための入口が増えるからである
- 作るもの 4 の一覧の守る仕組みの列：型の「並べ替えと上限を持たない」は機械で落とす spec が無いので、レビューが見ると書いた
- 計画の壊して落ちる記録の表の 2 行が、実物と違った。`permitting_suppliers_sql` から `Scope` を外したときに `partner_shipments_spec.rb` の付与の無い関係の example は落ちない（付与を消した関係は、RLS の下でも行を返さない）。`ItemLabels.find` から `Scope` を外したときに他社の写しの example は落ちない（RLS が他社の写しを隠す）。どちらも `cross_read!` の example だけが落ちる。計画の表の 2 行を、落ちた example に直した

#### RED

期待の不一致で落ちたものは、計画が名指しした 3 つである。

| spec | 流した版 | 落ちた example | 落ち方 |
|---|---|---|---|
| `packs/fulfillment/spec/public/fulfillment/partner_shipments_spec.rb` と入口の行列の `PurchaseOrder.supplierShipments` | ガード（`spec/support/public_api_returns.rb` と `rails_helper.rb` の取り付け）だけを足し、`permitting_suppliers` を直す前の `42d5416` のコード | 前者の 5 つすべてと、後者の 10 行すべて（5 examples, 5 failures と 10 examples, 10 failures） | `PublicApiReturns::Violation: Partnerships::Access.permitting_suppliers が ActiveRecord::Relation を返した` |
| `packs/inventory/spec/public/inventory/adjustment_spec.rb` | 写しの確かめの example を足し、`Inventory::Adjustment` を直す前のコード | 写しの無い品目 ID と他社の写しの品目 ID の `adjust`・`set_quantity` の 2 つと、`cross_read!` の 2 つ（10 examples, 4 failures） | `expected: [[:not_found, [:item_id]]] got: []` |
| `packs/notifications/spec/models/notifications/provider_spec.rb` | 期待を書き換え、`Setup.verify!` を直す前のコード | 起動時の確かめの example（5 examples, 1 failure） | `expected: nil got: Notifications::FakeProvider` |

次の spec は、足したメソッドが無いと読み込みの失敗（`NoMethodError`・`NameError`）でしか落ちないか、振る舞いを変えずに置き場を移す直しなので、壊して落ちる記録で RED に代える。ガードの spec の (i)〜(iv) は、補助が無いと読み込みの失敗でしか落ちない。

- `spec/platform/public_api_returns_spec.rb`（(i)〜(iv)）
- `packs/partnerships/spec/public/partnerships/access_spec.rb` の `permitting_supplier_ids`・`permitting_suppliers_sql` の 3 つと `show_partner_code?` の 1 つ、`packs/platform/spec/models/sql_subquery_spec.rb`
- `packs/inventory/spec/public/inventory/item_labels_spec.rb` の `.find` の 2 つ、`stocks_spec.rb` の並びと上限の 2 つ
- `spec/packwerk/entry_callers_spec.rb`、`spec/scenarios/demo_world_spec.rb` の表と対象の example

#### ガードと写しで落ちた spec

作るもの 1 のガードを入れ、`permitting_suppliers` を直した後に全件を流した（`0bef45f` の前の作業ツリー、`bundle exec rspec`）。3129 examples, 3 failures で、落ちたのは `page_spec.rb:267`・`:279`・`:287` だけだった。どれも `Page.of(...) { _1 }` が行のモデルを `values` で返すので、ガードの `Page#values` の確かめが例外にした。ブロックを `{ _1.map(&:id) }` に直した。`receivers_spec.rb`・`bullet_spec.rb`・`query_budget_spec.rb` の `and_wrap_original` は、ガードを付けた後も通った。

作るもの 2 で調整と在庫数の設定が写しを求めるようにした後、`git grep` で調整・在庫数の設定・`adjustStock`・在庫の取り込みを呼ぶ spec（30 の spec のファイル）と `spec/matrix`・`packs/inventory/spec` を流した。1869 examples, 68 failures で、計画の一覧の spec のほかに落ちた spec は無かった。`spec/requests/imports_spec.rb` の在庫の取り込みの example は、この grep に当たらず、`bin/ci` の全件で落ちた（`appliedRows` が 0）。同じく品目を `:labeled` にした。

| spec | 落ちた数 | 直し方 |
|---|---|---|
| `allocation_spec.rb`・`shipping_spec.rb`・`shipping_lock_spec.rb`・`post_shipment_audit_spec.rb`・`stock_allocation_spec.rb`（乱数の品目 ID） | 6・9・7・1・2 | 同じ品目 ID の写しを `:item_label` の factory で作る。競合テストは後始末の表に `item_labels` を足す |
| `order_allocation_spec.rb`・`cancellation_reviews_spec.rb`・`order_cancellation_spec.rb`・`order_allocation_lock_spec.rb`・`cancel_vs_ship_spec.rb`（写しの無い factory の品目） | 2・4・7・1・4 | 品目を `:labeled` の trait で作る。競合テストは後始末の表に `item_labels` を足す |
| `parallel_imports_spec.rb`・`run_job_spec.rb`（在庫の CSV） | 2・10 | 在庫の取り込みに使う品目を `:labeled` で作る |
| `spec/requests/inventory_spec.rb`・`log_hygiene_spec.rb`・`shipping_spec.rb`・`supplier_shipments_spec.rb` | 2・1・2・6 | 同上 |
| 入口の行列の `Mutation.adjustStock` | 2 | 世界の品目の表ごとの行に写しを書く（`matrix_world.rb`）。期待は変えずに通った |

`dashboard_spec.rb` は落ちなかったが、作るもの 3 の C で写しのコードで並べるので、在庫の品目を `:labeled` にした。

#### 壊して落ちる記録

壊す前にファイルを一時の置き場に複製し、複製から戻した。数は、壊した版でそこに書いた spec だけを流した結果である。

| 壊し方 | 落ちた example |
|---|---|
| permitting_suppliers_sql が relation を返す | `partner_shipments_spec.rb` の 5 つ・`graphql_matrix_spec.rb` の 11 つ（16 examples, 16 failures） |
| ガードから Relation を外す | `public_api_returns_spec.rb:98`、`public_api_returns_spec.rb:122`（5 examples, 2 failures） |
| ガードから Base を外す | `public_api_returns_spec.rb:138`、`public_api_returns_spec.rb:98`（5 examples, 2 failures） |
| OperationResult をたどらない | `public_api_returns_spec.rb:98`（5 examples, 1 failure） |
| Hash のキーをたどらない | `public_api_returns_spec.rb:98`（5 examples, 1 failure） |
| Hash の値をたどらない | `public_api_returns_spec.rb:98`（5 examples, 1 failure） |
| Set をたどらない | `public_api_returns_spec.rb:98`（5 examples, 1 failure） |
| 配列をたどらない | `public_api_returns_spec.rb:138`、`public_api_returns_spec.rb:98`（5 examples, 2 failures） |
| Data をたどらない | `public_api_returns_spec.rb:98`（5 examples, 1 failure） |
| Page#values を確かめない | `public_api_returns_spec.rb:138`（5 examples, 1 failure） |
| glob から sales を外す | `public_api_returns_spec.rb:83`（5 examples, 1 failure） |
| 確かめない種類に Module を足す | `public_api_returns_spec.rb:83`（5 examples, 1 failure） |
| TracePoint の代わりに prepend で包む | `public_api_returns_spec.rb:122`（5 examples, 1 failure） |
| permitting_supplier_ids から権限の条件を外す | `access_spec.rb:80`、`access_spec.rb:95`（23 examples, 2 failures） |
| permitting_supplier_ids から Scope を外す | `access_spec.rb:95`、`access_spec.rb:105`（23 examples, 2 failures） |
| permitting_suppliers_sql から Scope を外す | `access_spec.rb:95`、`access_spec.rb:105`（23 examples, 2 failures） |
| contains を常に真にする | `sql_subquery_spec.rb:10`・`access_spec.rb:80`、`access_spec.rb:105`・`partner_shipments_spec.rb:60`（25 examples, 4 failures） |
| adjust・set_quantity の写しの確かめから Scope を外す | `adjustment_spec.rb[3:3:1]`、`adjustment_spec.rb[3:3:2]`（10 examples, 2 failures） |
| adjust・set_quantity の写しの確かめを消す | `adjustment_spec.rb` の 4 つ（10 examples, 4 failures） |
| adjust だけ写しの確かめを消す | `adjustment_spec.rb[3:1]`、`adjustment_spec.rb[3:3:1]`（10 examples, 2 failures） |
| ItemLabels.find から Scope を外す | `item_labels_spec.rb:92`（8 examples, 1 failure） |
| below_safety_stock を品目 ID だけで並べる | `stocks_spec.rb:39`、`stocks_spec.rb:51`・`dashboard_spec.rb:119`（26 examples, 3 failures） |
| 写しの無い在庫を先に並べる | `stocks_spec.rb:39`（26 examples, 1 failure） |
| below_safety_stock の limit を外す | `stocks_spec.rb:51`・`dashboard_spec.rb:119`（26 examples, 2 failures） |
| show_partner_code? を true にする | `access_spec.rb:206`・`graphql_matrix_spec.rb` の 5 つ（15 examples, 6 failures） |
| verify! が作り直しをやめる | `provider_spec.rb:24`（5 examples, 1 failure） |
| Operations の表から correct_item_price を消す | `demo_world_spec.rb` の 4 つ（4 examples, 4 failures） |
| grant_permission に対象を渡さない | `demo_world_spec.rb` の 4 つ（4 examples, 4 failures） |
| 対象の食い違いの例外を外す | `demo_world_spec.rb:266`（4 examples, 1 failure） |
| E の spec が受け手の参照を集めない | `entry_callers_spec.rb:221`（6 examples, 1 failure） |
| E の spec が呼んでよい場所を広げる | `entry_callers_spec.rb:231`（6 examples, 1 failure） |
| E の spec が require_tenant! を集めない | `entry_callers_spec.rb:186`、`entry_callers_spec.rb:249`（6 examples, 2 failures） |
| E の spec が非公開の特異メソッドをたどらない | `entry_callers_spec.rb:186`、`entry_callers_spec.rb:249`（6 examples, 2 failures） |

`access_spec.rb:95`（知らない権限は例外）が `Scope` と権限の条件を外す壊し方でも落ちたのは、壊した版が共通の非公開の補助（`permitting`）を通らない形にしたので、権限の確かめも一緒に外れたからである。`demo_world_spec.rb` の表から操作を消す壊し方と対象を渡さない壊し方は、世界を作る `DemoWorld.build` が同じ操作を呼ぶので、グループの 4 つすべてが落ちた。

落ちなかったもの：

- `DemoWorld::Operations` の対象の食い違いの例外を外しても、計画の example（表と、各操作が対象を渡すか）は落ちない。対象の有無が合っていれば例外の分岐を通らないからで、食い違えて呼ぶ example を足すと、それだけが落ちた（上の表）
- E の spec が受け手の参照を集めないとき、本体のコードの (i) は落ちず、(i) の負例だけが落ちる。本体のコードに受け手の参照が無いので、集めなくても空になる

### 確かめたこと

#### 手元で流したもの

```sh
TEST_DATABASE=factory_ops_m55_test BASE_REF=origin/m54-same-tenant-sync bin/ci   # c831336 で、すべての工程が通った。rspec は 3145 examples, 0 failures
bin/check-open-items --due M55 && bin/check-commit-refs   # 通った
git grep -nw permitting_suppliers -- . ':!docs/plans' ':!docs/implementation-plan.md'   # 0 件
git grep -n -e '在庫は品目コードを持たない' -e '品目の存在は呼ぶ側' -e '在庫は受注に依存しないので、品目が自社のものか' -e '業務の言葉を持たず' -- . ':!docs/plans' ':!docs/implementation-plan.md'   # 0 件
git grep -n ACL -- . ':!docs/plans' ':!docs/implementation-plan.md'   # architecture/decisions.md の権限表の 1 行だけ
cd frontend && npm run codegen:check && npm run lint && npm run typecheck   # 通った（Node 22、npm ci の後）
cd frontend && E2E_DATABASE=factory_ops_m55_e2e PLAYWRIGHT_CHANNEL=chrome npm run test:e2e   # c831336 で 74 passed・26 skipped（1.9 分）
```

`bin/packwerk validate && bin/packwerk check` は依存を変えずに通った。分岐の網羅率の警告は、`c831336` の `bin/ci`（基準は `42d5416`）で 0 件だった。公開 API の戻り値のガードの「どの spec も呼ばなかった」一覧は、全件では出なかった（0 件）。`6a1ed61` の最初の `bin/ci` は、上の `imports_spec.rb` の 1 件で落ちた。

「腐敗防止層」が残る行は次のとおりで、どれも品番の読み替え（翻訳）の役を指す。`context-map.md` の関係の表の「購買 → 受注」の種類と説明の行・「発注の連結と品番の照合」の手順 2、`handoff.md` の品番の行、`showcase.md` の 3 行（何を示すかの文・腐敗防止層の箇条・spec のコメント）、`purchase_order_translator.rb` と `purchase_order_translator_spec.rb` の冒頭のコメント。

rspec の件数は、M54 の 3119 から 3145 になった。

### 残件の処理

引当先が M55 の行（OI-215〜OI-218。どれも `decided`）は、着手の前と PR の前に台帳を読み、作るもの 1〜4 で反映した。OI-219（`judgment`）は計画のとおりに作った。計画が書き切らなかった 3 つを OI-224 に `judgment` で積み、戻り値のガードの確かめの外を IB-150 に積んだ。取りまとめ役の判断の受け口（`decisions.md`）は、着手の時と各 commit の前と報告の前に読み、どの時点でも空だった。
