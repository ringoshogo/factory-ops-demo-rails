# サイクル 09 の計画レビュー：M52 と、M33・M41 の残り

この文書は、`implementation-plan.md` の M52 と、M33・M41 の「残り（サイクル 09）」を 2 系統の独立したレビュー（Claude と Codex）にかけ、指摘を計画に反映した記録である。M52 から着手する担当者と、計画をレビューする人が読む。担当者は、計画の節が「なぜこう書いてあるか」をここで引ける。

サイクル 09 に入るのは、サイクル 08 の逸脱検査と改善の探索で起こした M52 と、サイクル 08 から移した M33・M41 の残りである。作者は 2026-10-16 に、サイクル 08 の終わりの問い（`plans/cycle-08/author-decisions.md`）に答えた。OI-205 の (a)（全 spec に効く around の補助を外し、落ちた example を包む around だけを個別に直す）は、サイクル 08 の末に M52 の作るもの 4 に入り、直す形と数え上げの方法をこの計画レビューで決めた（下の「M52 の around の数え上げ」）。決めた形は OI-209（`judgment`）に書いた。OI-206・OI-204・IB-101 は既定のままで、作るものは変わらない。IB-133 の答え（M41 の残りを毎サイクル移し続ける）を、M41 の「残り（サイクル 09）」に書いた。IB-130 の答え（前の担当の一時の DB 13 個を取りまとめ役が消す）は、サイクル 08 の末に取りまとめ役が済ませた。

## マイルストーンの分け方

| マイルストーン | 中身 | 分けた理由 |
|---|---|---|
| M52 テストの基盤と CI の守りのガードを足す | E2E の起動の時の読み込みのガード（OI-207）、`publish` の `if:` の迂回を止める期待（IB-134）、担当を止める手順を 1 か所にする（OI-208）、テナントで包む around の個別の直し（OI-205・OI-209） | サイクル 08 の逸脱検査と改善の探索で起こした。OI-205 は M51 で足した補助の置き換えで、M51 の基盤にガードを足す M52 と同じく、テストの基盤を直す。別のマイルストーンにすると、同じ `spec/rails_helper.rb` と `guides/testing.md` を 2 回直す |
| M33 の残り | 作者の画面の指摘を待つ OI-177 | 作るものは無い。指摘が来たら、M33 の節の OI-177 の行の手順で直す |
| M41 の残り | 作者の実機の手順（OI-196） | 作るものは無い。作者は 2026-10-16 に、結果が来るまで毎サイクル移し続けると答えた（IB-133） |

実装の順は M52 だけで、M33 と M41 の残りは作者の指摘と結果が書かれたときに片付ける。M52 は、改善の探索で採用した変更をサイクルの最初に置く規則（`guides/dev-cycle.md`「全体の流れ」）により、サイクルの最初に置く。M52 の中では、作るもの 4 → 1 → 2 → 3 の順に勧める。4 は `spec/rails_helper.rb` と 18 個の around を書き換え、全 spec の流れに効くので、ほかのガードより先に入れて、後の 3 つの CI をその形で回す。3 は `origin/main` のマージを伴うので最後に置き、マージの前の commit で 1・2・4 の確かめを終えておく。

サイクル 09 は 3 つで、1 つのサイクルの上限に収まる。

## M52 の作るもの 3 の土台（#85）

サイクル 08 の末のブランチの先端 `63cfd3c` は、main に入った #85（担当を止める段落）を含まない。サイクル 08 の担当が、#85 の前から切ったサイクルの列を積み重ねたからである。2026-10-16 に `git merge-base --is-ancestor` で、#85 のマージの commit も #85 の先端も `63cfd3c` の祖先でないことを確かめ、`git merge-tree --write-tree 63cfd3c origin/main` で衝突なしにマージできることを確かめた。`origin/main` にあって `63cfd3c` に無い変更は、#85 と Dependabot の lucide-react の更新（#77）の 2 つである。

計画の前の版は、ブランチが #85 を含まないなら引当先を書き換えるとしたが、サイクル 09 に後ろのマイルストーンは無い。#85 の段落を cherry-pick で写すと、main と M52 のブランチがそれぞれ同じ場所に違う段落を足した形になり、作者のマージでぶつかる。M52 の担当が `origin/main` をマージすると、マージの基点が main の先端に進み、作るもの 3 の書き換えは main に対する差分になる。そのため、OI-208 の引当先は M52 のままにし、作るもの 3 の前に `origin/main` をマージすると書いた。

## M52 の around の数え上げ

2026-10-16 に、`63cfd3c` の `spec/**/*.rb` と `packs/*/spec/**/*.rb` を Prism で読み、`around`・`prepend_around`・`append_around` の呼び出しを 35 個数えた。`example.run` の後に送出しうるかで、次のとおり分けた。

| 分け | 数 | 場所 | 直すか |
|---|---|---|---|
| `Tenancy.with_tenant` で example を包む | 18 | `packs/fulfillment/spec`（`shipment_request_status_spec.rb`・`instructions_spec.rb`・`shipping_spec.rb`）、`packs/inventory/spec`（`stock_spec.rb`・`adjustment_spec.rb` の 2 つ・`allocation_spec.rb`）、`packs/purchasing/spec`（`purchase_order_status_spec.rb`）、`packs/sales/spec`（`item_prices_constraints_spec.rb`・`item_price_spec.rb`・`sales_order_status_spec.rb`・`cancellation_reviews_spec.rb`・`catalog_spec.rb`・`item_prices_spec.rb`・`order_allocation_spec.rb`・`order_cancellation_spec.rb`・`part_mappings_spec.rb`・`purchase_order_translator_spec.rb`） | 直す。example が SQL のエラーで落ちると、セーブポイントの解放と `Tenancy.reset!` が中断したトランザクションで失敗し、around から送出する |
| `Rails.event` の購読と解除 | 5 | `packs/imports/spec`（`parallel_imports_spec.rb`・`run_job_spec.rb`）、`packs/notifications/spec`（`best_effort_mail_job_spec.rb`・`critical_delivery_job_spec.rb`・`sendgrid_spec.rb`） | 直さない。解除は SQL を流さない |
| `Dir.mktmpdir` の作業の置き場 | 5 | `spec/bin`（`check_branch_coverage_spec.rb`・`check_commit_refs_spec.rb`・`check_open_items_spec.rb`・`test_layers_spec.rb`）、`spec/graphql/schema_compat_spec.rb` | 直さない。後始末はファイルの削除で、example の DB の状態で変わらない |
| 環境変数と設定の値を戻す | 3 | `spec/requests/maintenance_mode_spec.rb`、`spec/platform/demo_reset_spec.rb`（`with_env`）、`spec/support/sendgrid_webhook.rb`（`with_public_key`） | 直さない。`ensure` で値を戻すだけ |
| `Bullet.profile` | 1 | `spec/support/bullet.rb` の `config.around` | 直さない。N+1 を見つけると `example.run` の後に送出するが、設定の段の around なので rspec-rails の around より外側にあり、巻き戻しの後に走る |
| 外す補助とその spec | 3 | `spec/support/around_hook_errors.rb`、`spec/platform/around_hook_errors_spec.rb` の 2 つ | 作るもの 4 で消す |

`Bullet.profile` が外側にあることは、rspec-core 3.13.6 のコードで確かめた。設定の段の around は、group を作るときの `configure_group` の最初の `register_globals` で末尾に足され、その後の `config.include`（rspec-rails の `MinitestLifecycleAdapter` と `AroundHookErrors`）と group の本文の `around` は先頭に足される（`hooks.rb` の `around` が `:prepend` で登録する）。`run_around_example_hooks_for` は並びの後ろのフックほど外側に包むので、設定の段の around が最も外側になる。下の試作の失敗の backtrace でも、`bullet.rb` の行が spec の around の行の外側にある。

### 試作

直す形を選ぶために、`63cfd3c` の作業ツリーで `spec/rails_helper.rb` の `config.include AroundHookErrors` を外し、一時の spec を置いて流した（`TEST_DATABASE=factory_ops_c09plan_test bundle exec rspec <一時の spec>`。一時の変更は戻し、commit していない）。

| around の形 | 落ちた example の後の開いたトランザクション（アプリ・所有ロール） | 後の `MatrixCrossRead.with_policies` |
|---|---|---|
| `Tenancy.with_tenant(id) { example.run }` | 1・1 | 「所有ロールの接続にトランザクションが残っている（1 段）」で失敗 |
| `Tenancy.with_tenant(id) { example.run; raise ActiveRecord::Rollback if example.exception }` | 0・0 | 通る |

後の形では、落ちた example は `PG::DivisionByZero` の失敗として報告され、次の example の中ではトランザクションが 2 段（example とセーブポイント）開き、テナントの設定が入っていた。

M50 の壊し方（`packs/sales/app/public/sales/item_prices.rb` の単価の式から `.current` を外す）で `bundle exec rspec packs/sales/spec/public/sales/catalog_spec.rb` を流すと、補助を外して around を直さない版は 19 examples・3 failures（壊した example と、後ろの `cross_read!` の 2 つのグループが「トランザクションが残っている」で落ちる）、`catalog_spec.rb` の around だけを後の形にした版は 19 examples・1 failure だった。M51 の後は、止まらずに残ったトランザクションで落ちる形になっている。

巻き戻すのを落ちた example に限ったのは、通った example の後始末を変えないためである。`Tenancy.with_tenant` のセーブポイントは、テストの外側のトランザクションの中で最初に結べるトランザクションなので、example の中の `after_commit` はこのセーブポイントの解放で走る。いつも巻き戻すと、通った example の後に `after_commit` の代わりに `after_rollback` が走る。
