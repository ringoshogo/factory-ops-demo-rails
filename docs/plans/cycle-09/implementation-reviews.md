# サイクル 9 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M52 テストの基盤と CI の守りのガードを足す：E2E の起動の時の読み込み、`publish` の `if:`、テナントで包む around

`m52-test-guards`（base は `main`）。サイクル 09 の計画の `cycle-09-plan` の先端 `9fbe840` から切った。計画の PR が未マージの間は、その commit も PR の差分に見える。M52 の差分は `9fbe840..` である。

（レビューの結果は PR を出した後に書く）

### 実装の記録

#### 計画との違い

- 作るもの 3（OI-208）は作らず、M54 の作るもの 8 に移した。計画は、作るもの 1・2・4 の先端で `git merge origin/main` を流して #85 を取り込んでから書くとしたが、マージのコマンドが実行の環境の権限で拒否された（`a2c8225` で `bin/ci` を通した後）。別の手で取り込まずに取りまとめ役に返し、作者が 2026-10-16 に、M52 から外し #85 を祖先に持つブランチで行うと決めた（受け口の D-1）。M52 のブランチに main のマージの commit は無く、差分は `9fbe840..` の 1 つの範囲である。計画の M52 の節（目的・作る順・作るもの 3・依存の表・実装する文書の節）と、M54 の節（作るもの 8・依存の表・実装する文書の節）と、`guides/dev-cycle.md`「全体の流れ」の表のサイクル 09 の行を直した。OI-208 は引当先を M54 にし、作者の判断を内容の欄の末尾に書いた。受け口は結果の欄に書くよう求めたが、`bin/check-open-items` が `open` の行の結果を落とすので、内容の欄にした
- 作るもの 4 の止まりを再現する example の後始末は、計画の「`ensure` で両方の接続を巻き戻す」では足りなかった。(i) の対照で内側の example の around が送出すると、rspec-rails の `after_teardown` が飛び、トランザクションのほかに、example の間だけスレッドをまたいで共有させた接続（activerecord 8.1.4 の `lib/active_record/test_fixtures.rb` の `teardown_transactional_fixtures` が呼ぶ `ConnectionPool#unpin_connection!`）も戻らない。接続を巻き戻すだけの形で `spec/platform/tenant_example_spec.rb` と `packs/sales/spec/concurrency/sales/cancellation_reviews_lock_spec.rb` を `--order defined` で続けて流すと、競合テストの 2 つのスレッドが同じ接続を使い、プロセスが CPU を使わずに 10 分を過ぎても終わらなかった。アプリの接続は `idle in transaction`（最後の問い合わせ `SELECT pg_backend_pid()`）だった。example を 1 つずつ前に置いて流し、(i) の後だけで止まることを確かめた。後始末を、内側の example の `after_teardown` を流してから両方の接続を巻き戻す形にし、同じ 2 つのファイルが 7 examples, 0 failures で終わることを確かめた。計画の作るもの 4 の節を直した（`99545f4`）。同じ事実を `spec/support/tenant_example.rb` の冒頭のコメントにも書いた。M51 の後に止まりが「トランザクションが残っている」で落ちる形に変わったのは後ろのグループが行列のグループだったときで、後ろが競合テストなら、飛んだ後始末は今も止まりになる。
- 作るもの 2 の壊し方のうち、否定の 2 つ（`!success() && …`・`!(success() && …)`）は、`if:` の値を `!` で書き始めると YAML のタグとして読まれ、`ci_checks_spec.rb` の全 example が `YAML.load_file` の失敗で落ちる。`if:` の期待を確かめたことにならないので、GitHub の式の書き方の `${{ }}` で包んで流した。計画の壊して落ちる記録の表を直した（`a2c8225`）。
- 作るもの 2 の `success()` の直後の照らし方は、`success()` の後の空白を除いた 2 文字までが空（式の終わり）か `&&` であることにした。`(a && success())` のように閉じ括弧が続く形も落とす。計画の「直後が `&&` か式の終わり」のとおりで、いまの式（`success() && github.event_name == 'push'`）は通る。

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
| 2 | `if:` を `success() == false && github.event_name == 'push'` にする | 同じ example だけが `success()` の直後の期待で落ちた |
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
git grep -n -e AroundHookErrors -e around_hook_errors -- . ':!docs/plans' ':!docs/implementation-plan.md'   # 0 件
TEST_DATABASE=factory_ops_m52_test bin/ci   # a2c8225 で、すべての工程が通った。rspec は 3122 examples, 0 failures
```

### 残件の処理

引当先が M52 の行は、着手の前と PR の前に台帳を読んだ。OI-207 は `a2c8225` で閉じた。OI-205・OI-209（どちらも `decided`）は作るもの 4 で反映した。OI-208 は作者の判断（受け口の D-1）で引当先を M54 に移した。IB-123 の反映先を `tenant_example.rb` に書き換え、IB-136 の結果の欄に、補助を外したので前提が無くなったことを書き足した。IB-134 は作るもの 2 で実装した。IB-138 は、計画のとおり、サイクル 09 の末の改善の探索で取りまとめ役が判定する。取りまとめ役の判断の受け口（`decisions.md`）で D-1 を読んだ。
