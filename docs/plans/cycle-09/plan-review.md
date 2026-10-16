# サイクル 09 の計画レビュー：M52・M53・M54 と、M33・M41 の残り

この文書は、`implementation-plan.md` の M52・M53・M54 と、M33・M41 の「残り（サイクル 09）」を 2 系統の独立したレビュー（Claude と Codex）にかけ、指摘を計画に反映した記録である。M52 から着手する担当者と、計画をレビューする人が読む。M53・M54 は、M52 のレビューを終えた後に作者の判断で足したので、記録を末尾の「作者の判断で足した M53・M54」に分けた。担当者は、計画の節が「なぜこう書いてあるか」をここで引ける。

サイクル 09 に入るのは、サイクル 08 の逸脱検査と改善の探索で起こした M52 と、サイクル 08 から移した M33・M41 の残りである。作者は 2026-10-16 に、サイクル 08 の終わりの問い（`plans/cycle-08/author-decisions.md`）に答えた。OI-205 の (a)（全 spec に効く around の補助を外し、落ちた example を包む around だけを個別に直す）は、サイクル 08 の末に M52 の作るもの 4 に入り、直す形と数え上げの方法をこの計画レビューで決めた（下の「M52 の around の数え上げ」）。決めた形は OI-209（`judgment`）に書いた。OI-206・OI-204・IB-101 は既定のままで、作るものは変わらない。IB-133 の答え（M41 の残りを毎サイクル移し続ける）を、M41 の「残り（サイクル 09）」に書いた。IB-130 の答え（前の担当の一時の DB 13 個を取りまとめ役が消す）は、サイクル 08 の末に取りまとめ役が済ませた。

初回のレビューは `38d64dd` を読んだ。依頼には読む版の commit を書き、その版を展開したディレクトリだけを読ませた。Claude は Conditional Go、Codex は Go で、High は Claude の 1 件だった。指摘を直した版（`daaab94`）に初回の記録を足した版（`cad3a70`。計画の節と台帳は `daaab94` と同じ）を、2 系統で読み直した（読み直し 1）。2 系統とも、初回の指摘の解消を認め、新しい High 以上は無く、Go だった。M52 から着手できる。読み直し 1 の結果は末尾の「読み直し 1」にある。Claude のサブエージェントは、2 回とも最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ（`guides/dev-cycle.md`「独立したレビュアー」）。Codex は、2 回とも展開したディレクトリが git のリポジトリでないので `--skip-git-repo-check` を付けて流し、一時の失敗は起こさなかった。

読む順は、マイルストーンの分け方 → 作るもの 3 の土台 → around の数え上げ → 判定 → 指摘ごとの対応 → 作者に渡すもの → 直さなかった指摘と台帳に積んだもの、である。指摘の出典は次の形で示す。2 系統の ID がぶつかるときは、`Codex M52-1` のように系統を添える。

| | Claude | Codex |
|---|---|---|
| 初回 | `<マイルストーン>-<番号>`（`M52-1` など） | `<マイルストーン>-<番号>` |
| 読み直し 1 | `R1-<マイルストーン>-<番号>` | `R1-<マイルストーン>-<番号>` |

## マイルストーンの分け方

| マイルストーン | 中身 | 分けた理由 |
|---|---|---|
| M52 テストの基盤と CI の守りのガードを足す | E2E の起動の時の読み込みのガード（OI-207）、`publish` の `if:` の迂回を止める期待（IB-134）、担当を止める手順を 1 か所にする（OI-208）、テナントで包む around の個別の直し（OI-205・OI-209） | サイクル 08 の逸脱検査と改善の探索で起こした。OI-205 は M51 で足した補助の置き換えで、M51 の基盤にガードを足す M52 と同じく、テストの基盤を直す。別のマイルストーンにすると、同じ `spec/rails_helper.rb` と `guides/testing.md` を 2 回直す |
| M33 の残り | 作者の画面の指摘を待つ OI-177 | 作るものは無い。指摘が来たら、M33 の節の OI-177 の行の手順で直す |
| M41 の残り | 作者の実機の手順（OI-196） | 作るものは無い。作者は 2026-10-16 に、結果が来るまで毎サイクル移し続けると答えた（IB-133） |

実装の順は M52 だけで、M33 と M41 の残りは作者の指摘と結果が書かれたときに片付ける。M52 は、改善の探索で採用した変更をサイクルの最初に置く規則（`guides/dev-cycle.md`「全体の流れ」）により、サイクルの最初に置く。M52 の中の順（作るもの 4 → 1 → 2 → 3）は、計画の節の冒頭に書いた。

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

## 判定

| マイルストーン | 初回 Claude | 初回 Codex | 読み直し 1 Claude | 読み直し 1 Codex |
|---|---|---|---|---|
| M52 | Conditional Go | Go | Go | Go |
| M33 の残り | Go | Go | Go | Go |
| M41 の残り | Go | Go | Go | Go |

初回の全体の判定は、Claude が Conditional Go、Codex が Go だった。High は Claude の M52-1 の 1 件で、Codex も同じ衝突を Medium（Codex M52-1）で挙げた。数え上げのガードと対照の置き方（計画の形）を変える直しなので、読み直しに出した。読み直し 1 は 2 系統とも Go で、ここで終えた。

2 系統が同じことを挙げた指摘は次の 1 つである。

- 数え上げのガードが、同じ spec に書く対照 (i) の直に包む around を落とし、完了条件の 0 failures と最初に落とす 18 個が成り立たない（Claude M52-1 は High、Codex M52-1 は Medium）

## 指摘と対応

重大度は、2 系統で違うときは高い方を採った。「直した節」は、断りが無ければ `implementation-plan.md` の M52 の節である。直した版は `daaab94` である。

### M52

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Claude M52-1・Codex M52-1 | High | ガードが対照 (i) の直に包む around を落とす。除外の仕方を担当が決めることになり、最初に落とす数も 18 と 19 で揺れる | 作るもの 4。直に包む around を、ガードの合成のソースの文字列から内側の group に `module_eval` で作り、spec のファイルに around のブロックとして書かない（Codex の提案）。ファイルの除外も名指しの除外も要らない。外すもの（補助と `around_hook_errors_spec.rb`）を最初に消し、次にガードを書く順にして、最初に落とす数を 18 に決めた |
| Claude M52-2 | Medium | 「`success()` の直前に `!` が無い」「`||` を含まない」では、`!(success() && …)`・`! success()`・`success() == false && …` が通る | 作るもの 2。`if:` が `!` を含まない、`||` を含まない、`success()` の直後が `&&` か式の終わり、の 3 つで照らす。4 つの迂回の形を壊して落ちる記録の表に書いた。マイルストーンの表の行の約束（否定か論理和で迂回すると落ちる）はそのまま成り立つ |
| Claude M52-3 | Medium | 補助を外すと、`example.run` の前に around が送出したとき（引数の `let`・`foreign`）の巻き戻しも失われるが、範囲外にも OI-209 にも書かれていない | 範囲外と OI-209。止まりではなく後ろのグループの連なった失敗になり、メッセージが前の example の around を指すこと、拾う形は rspec-core の skip との関係を決める必要があり作者が退けた全体の補助に近づくことを、扱わない理由に書いた |
| Claude M52-4 | Medium | `git grep` の確かめが、計画の M52 の節と証跡に当たり、書いたとおりには 0 件にならない | 完了条件に `git grep -n -e AroundHookErrors -e around_hook_errors -- . ':!docs/plans' ':!docs/implementation-plan.md'` を 0 件として書き、文書に残すことの文を消した |
| Claude M52-5 | Medium | `origin/main` をマージした後のレビューの範囲、載せ直しの手順、#77 を含む先端での確かめが書かれていない | 作るもの 3。マージの前に共通の完了条件を通し、マージの後の先端で共通の完了条件と `frontend` の検査と E2E を流し直す。レビューの範囲をマージの commit の前と後の 2 つに分け、下の段が変わったら rebase せずに下の段の先端をマージする |
| Codex M52-2 | Medium | 通った example のセーブポイントを解放する性質（`after_commit` の時機）を守る example が無く、いつも巻き戻しても通る | 作るもの 4 の (iv)。通る example が `ApplicationRecord.current_transaction` に登録した `after_commit` だけが走ることを確かめ、条件を外していつも巻き戻す壊し方を記録の表に書いた |
| Codex M52-3 | Medium | `pending` の example の例外は `execution_result.pending_exception` に置かれ、`example.exception` だけでは巻き戻さない | 作るもの 4 の包みの補助と (iii)。巻き戻す条件に `pending_exception` を足し、`pending` の中の SQL のエラーの後もトランザクションが残らない example と、条件から外す壊し方を書いた。OI-209 も直した |
| Claude M52-6 | Low | ガードの合成のソースと壊し方が、`around` の中の `with_tenant` だけで、`transaction` と `prepend_around`・`append_around` を外しても落ちない | 作るもの 4 の数え上げのガード。合成のソースを 4 つにし、探す名前を 1 つずつ外す 4 つの壊し方を記録の表に書いた |
| Claude M52-7 | Low | `ActiveRecord::Rollback` の扱い・`after_commit` の時機・`Procsy#exception`・`MinitestLifecycleAdapter` の原文を引いていない。出典に挙げた `around_hook_errors.rb` は同じマイルストーンで消える | 作るもの 4。rspec-core・rspec-rails・activerecord の原文の場所を添え、補助の冒頭のコメントに原因と巻き戻しを限る理由を移すと書いた |
| Claude M52-8 | Low | M52 で中身が片付くか前提が消える IB-123・IB-136・IB-138 の扱いが無い | 文書に残すこと。実装者が IB-123 の反映先と IB-136 の結果の欄を書き足し、IB-138 は取りまとめ役がサイクル 09 の末の改善の探索で判定する |

### M33 の残り・M41 の残り

2 系統とも指摘なしだった。

## 作者に渡すもの

### 答えで作るものが変わる問い

新たに起こした問いは無い。

### 確かめるだけの判断

| ID | 判断 | 違う形を求めるときに替える場所 |
|---|---|---|
| OI-209 | OI-205 の (a) の直す形（`TenantExample.run` で落ちた example のときだけ巻き戻す）と、数え上げのガード（Prism で around の中の `with_tenant`・`transaction` を落とす）。`example.run` の前の送出は扱わない | M52 の作るもの 4。ガードを外すなら `spec/platform/tenant_example_spec.rb` の 1 つの example、around を 1 つずつ書き下すなら 18 個の around |

### 値の差し替え・受け入れ・実機の確かめで済む問い

| ID | 問い | 既定 | 替える場所 |
|---|---|---|---|
| OI-196 | 公開の配置の実機の手順の結果（実機の確かめ） | — | `deploy/README.md`「作者の手順」1〜6 を流し、結果を PR か台帳に書く。結果が来るまで M41 の残りを毎サイクル移す（IB-133） |
| OI-177 | M33 の画面の細かい指摘 | — | 指摘を出したら、M33 の節の OI-177 の行の手順で直す |

## 直さなかった指摘と、台帳に積んだもの

- 指摘は、どれも計画の直しで扱った
- 違和感のうち計画で扱ったもの（Claude）：対照 (i) は補助を外した後でないと成り立たないことは、外すものを最初に消す順にした。作るもの 1 の渡さないときの `E2E_EAGER_LOAD` は、子のプロセスの環境で `nil` で消すと書いた。ガードが字面で探すことは、`testing.md`「層への配分」に書くとした。`matrix_cross_read.rb` の失敗のメッセージは、「層への配分」を指す文を足すとした
- Codex の違和感は「なし」だった。改善の候補に移したものは無い

## 読み直し 1

指摘を直した版を、初回の指摘が解消したかと、High 以上の新しい指摘だけで判定させた（`guides/dev-cycle.md`「判定の形」）。2 系統とも、初回の 10 件（2 系統が同じことを挙げた 1 件を含む）の解消を認め、新しい High 以上は無く、全体を Go とした。Claude は、展開したディレクトリの spec を Prism で読み直し、around の中に `with_tenant` か `transaction` を持つものが 19 個（`around_hook_errors_spec.rb` の 1 個を除いて 18 個）で、計画と合うことを確かめた。読み直しで出た Medium 以下は、読み直しには出さずに直した。

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Claude R1-M52-1 | Medium | 対照 (i) が内側の example の落ち方を照らさず、合成のソースの字面（引数の無い `with_tenant`）のまま流すと、`example.run` の前の `ArgumentError` でも同じく残って通る | M52 の作るもの 4。(i) に、内側の example が `/division by zero.*current transaction is aborted/m` の失敗として報告されることを足し、(i) が流す合成のソースを `Tenancy.with_tenant(SecureRandom.uuid) { example.run }` の実行できる形にした |
| Codex R1-M52-1 | Medium | マージの前に共通の完了条件を通すとしたが、`--due M52` は作るもの 3 で閉じる OI-208 で落ちる | M52 の作るもの 3。マージの前は `--due M52` を除き、作るもの 3 を終えて OI-208 を閉じた後の先端で、`--due M52` を含む共通の完了条件と `frontend` の検査と E2E を流す |
| Claude R1-M52-2 | Low | ガードの対照「`TenantExample.run` を呼ぶ around が 1 つ以上ある」は、自分のファイルの内側の group だけで満たせ、`packs/*/spec` の glob が壊れても通る | M52 の作るもの 4。対照を、`packs/` の下のファイルに `TenantExample.run` を呼ぶ around があることにした |

違和感：

- 冒頭の段落が、読み直し 1 の結果がある前提で書かれていた（Claude）：読み直し 1 の結果を受けて、冒頭と判定の表を 2 回分の記録にそろえた
- 巻き戻す条件は rspec-core の `Example#display_exception` と同じ値である（Claude）：補助のコメントにそのことを書くと、作るもの 4 に足した
- Codex の違和感は「なし」だった。改善の候補に移したものは無い

## 作者の判断で足した M53・M54

M52 の読み直し 1 を終えた後、作者は 2026-10-16 の議論で 2 つの判断を出した（OI-210・OI-211）。取りまとめ役が、受け口に D-1 として書き、調査の担当の記録と一緒に渡した。D-1 は、2 つをマイルストーンとして起こし、台帳に `decided` の行と起票済みの改善の候補を足し、M52 と同じく 2 系統のレビューにかけるとした。

| マイルストーン | 中身 | 台帳 |
|---|---|---|
| M53 発注の詳細に、進みのタイムラインを出す | 購買の公開 API `timeline_for`、`PurchaseOrder.timeline`、画面の部品。受注側から届く 5 つのイベントに発生の時刻を運ばせる | OI-210（作者の判断、(a)）・OI-212（judgment）・IB-139 |
| M54 同じテナントの中の受注と出荷・請求を、同期の呼び出しでつなぐ | 出荷が受注を読み、呼ぶ。受注が請求を呼ぶ。出荷停止の表と 4 つのイベントと受け手を消し、「出荷可能」だけを残す。ADR 012 | OI-211（作者の判断、案 2）・OI-213（judgment）・IB-140 |

サイクル 09 は M52・M53・M54 と 2 つの残りで 5 つになり、上限の 6 つに収まる。実装の順は D-1 の既定のまま、M52 → M53 → M54 にした。M53 は購買の中で閉じ、小さい。M54 を先にする理由は見つからなかった。2 つは、受注側のイベントの発行（審査の決着と受注の取消）で同じファイルを直す。M53 が足す `occurred_at` は、M54 が消さないイベント（取消承認・取消却下・受注取消）に載るので、M53 を先にすると、M54 はその発行を同期の形に書き換えるときに一緒に読める。

### M53 で決めたこと

作者は、イベントに発生の時刻を運ばせるかを M53 で決めるとした。計画は、運ばせる形にした（OI-212）。いまの発注の時刻列は、受注側で起きた時刻ではなく、受け手がイベントを受け取った時刻（`Time.current`）である（`Purchasing::SupplierEventReceiver`）。配送は普段なら数秒しか遅れないが、ワーカーが止まると遅れが伸び、その間に発注側で起きた出来事（取消依頼）が受注確定より前に並ぶ。運ばせる費用は、5 つのイベントの型に 1 つずつ項目を足し、足す前のペイロードに空を足すこと（前例：`Contracts::SalesOrderReadyForShipment.from_payload`）で、小さい。

### M54 の調べ

調査の担当が `63cfd3c` を読み、取りまとめ役が主な主張を手元で確かめた（`fulfillment` の `package.yml` が `sales` に依存しないこと、`Purchasing::SupplierEventReceiver` が受け取った時刻を書くこと、流用元の計上が 1 つのトランザクションであること、GraphQL の `PurchaseOrder` に受注確定の時刻が無いこと）。計画レビューの担当は、`packs/*/package.yml`・配送表・受け手・ロックの箇所を読み直した。

同じテナントの中の非同期の経路は、配送表（`Contracts::Subscriptions`）の 16 経路のうち 6 つで、宛先はどれも受注側テナントである。

| イベント | 発行元 | 受け手 | M54 で |
|---|---|---|---|
| 出荷可能 | `Sales::OrderAllocation` | `Fulfillment::SalesEventReceiver` | 残す |
| 出荷停止 | `Sales::PurchasingEventReceiver.review` | 同上 | 消す。審査の行から導出する |
| 出荷停止解除 | `Sales::CancellationReviews.reject` | 同上 | 消す。審査の決着から導出する |
| 出荷取消 | `Sales::OrderCancelling.cancel` | 同上 | 消す。受注の取消から導出する |
| 出荷計上（受注への分） | `Fulfillment::Shipping.post` | `Sales::FulfillmentEventReceiver` | 消す。計上が `Sales::OrderShipping.mark_shipped` を呼ぶ。購買への分は残す |
| 請求対象確定 | `Sales::PurchasingEventReceiver.inspect_shipment` | `Billing::SalesEventReceiver` | 消す。`Billing::BillableItems.confirm` を呼ぶ |

依存の向きは、`sales` が `platform`・`partnerships`・`contracts`・`inventory`・`notifications` に、`fulfillment` が `platform`・`partnerships`・`contracts`・`inventory` に、`billing` が `platform`・`partnerships`・`contracts` に依存する（`63cfd3c` の `package.yml`）。`fulfillment` → `sales` と `sales` → `billing` を足しても、`sales` は `fulfillment` に、`billing` は `sales` に依存しないので、循環しない。`purchasing` → `sales` → `billing` の鎖も一方向である。

ロックの順は、2 つの案を比べた。いまは、受注の取消が受注 → 受注明細 → 在庫 → 引当、計上が出荷依頼 → 出荷指示 → 在庫 → 引当で、受注と出荷は互いの行をロックしない（`architecture/data-model.md`「取消と出荷の競合を止める場所」）。M54 では計上が受注の `shipped_at` を書き、出荷指示の作成と計上が受注の取消と審査を読むので、出荷が受注の行をロックする。

| 案 | 順 | 計画の判断 |
|---|---|---|
| 受注を先に取る | 受注 → 出荷依頼 → 出荷指示 → 在庫 → 引当 | 採る。取消・審査の作成と決着・出荷指示の作成・計上が、どれも受注の行ロックを最初に取り、そこで直列になる。流用元と同じ（`orders` から取る）で、ロックの順が 1 本になる。計上は、出荷依頼をロックせずに引いて受注 ID を読み、受注をロックしてから出荷依頼をロックして読み直す |
| 出荷依頼を先に取る | 出荷依頼 → 出荷指示 → 受注 → 在庫 → 引当 | 退ける。受注は出荷の行をロックしないので循環はしないが、計上は受注を待つ間も出荷依頼と出荷指示のロックを持ち続け、取消済と審査中の確かめが出荷のロックの後になる。順が受注の取消（受注が先頭）と食い違い、2 本の順を文書で説明し続けることになる |

注意すること：受注を取り消しても、出荷指示の行は `active` のまま残る。`ShippingInstruction.active` を数える箇所（`shipment_requests.rb` の出荷指示の読み込みと件数）は、取消済の受注の出荷依頼の指示を除く（調査の担当の Codex の系統も同じことを挙げた）。

退けた形：受注が出荷を呼ぶ形（出荷計上の受注への分が非同期のまま残り、上流が下流に依存する。取消は在庫より前に出荷依頼をロックするよう順を変えないとデッドロックする）、出荷依頼の写しを無くす形（作業が大きく、デッドロックの対策にならない）、ルートパッケージで束ねる形（`context-map.md`「疎結合を守る規則」5 に反し、「出荷停止」は `Sales::PurchasingEventReceiver` の中から出るので束ねられない）、`Contracts.publish` が同じテナントの受け手をすぐに呼ぶ形（取消と計上が逆の順でロックを取り、デッドロックする）。どれも ADR 012 に書く（M54 の作るもの 7）。

### M53・M54 の判定

M53・M54 の初回は `6a3ebc0` を読んだ。M52 と同じく、読む版を展開したディレクトリだけを読ませ、Codex は `--skip-git-repo-check` を付けて流した。Claude のサブエージェントは最終報告を返さずに終わり、結果のファイルから読んだ。

| マイルストーン | 初回 Claude | 初回 Codex |
|---|---|---|
| M53 | Conditional Go | Conditional Go |
| M54 | Go | Conditional Go |

High は 3 件だった（Claude M53-1 と Codex M53-2 は同じ）。どれも計画の形（値の項目・検査の置き場・書き込みの入口の契約）を変える直しなので、読み直しに出した。直した版は `01854af` である。

### M53・M54 の指摘と対応

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Claude M53-1・Codex M53-2 | High | 発注の詳細の `query_budget_spec.rb` の行は同じ発注の下の入荷を増やして比べるので、発注のフィールドの `timeline` を足すと落ちる。`PublicApiSource` で呼ぶ公開 API は `NESTED_APIS` の行を求める | M53 の作るもの 3 と完了条件。`query_budget_spec.rb` には足さず、`NESTED_APIS` に `timeline_for` の行を足す。一括の読み込みは、単体で SQL の件数（1 回）で確かめる |
| Codex M53-1 | High | 型の認可をそろえる先の `PurchaseOrderPolicy#show?` は値の `owner_tenant_id` を読むが、値に無い | M53 の作るもの 2。値に `owner_tenant_id` を持たせ、`Scope` を通した自社の発注から入れ、フィールドには出さない。request spec で空でない `timeline` が認可を通ることを確かめる |
| Codex M54-1 | High | 新しい書き込みの入口（`mark_shipped`・`confirm`）の引数・操作者・テナントの設定・見えない ID の扱いと、テナントの境界への影響が書かれていない（Claude M54-2 も Medium で挙げた） | M54 の作るもの 2・4。`OrderShipping` の 3 つは `Scope` の自社の受注だけを読み書きし、見えない受注には書かずに `NOT_FOUND`。`confirm` は操作者を取らず、テナントの設定を求め、所有テナントを `Current.tenant_id` で書く。それぞれの単体で、他社の ID・RLS を開いたとき・冪等・設定の無いときを確かめる |
| Claude M53-2・Codex M53-3 | Medium | 取消却下の発行元に、自動の却下（`PurchasingEventReceiver.publish_rejected`）が漏れている。`confirmed_at` を渡すことも書かれていない | M53 の作るもの 1 と完了条件。発行元を 5 つ挙げ、各発行元の spec に `occurred_at` の example を置き、`packs/sales/spec` を完了条件に足した。OI-212 も合わせた |
| Claude M53-3 | Medium | `NESTED_APIS` の行と、他社の発注の ID を渡す単体が無い | M53-1 の直しと、単体の他社の行の example（自社と他社の発注の ID を両方渡す） |
| Claude M53-4 | Medium | 同じ発注の明細 2 行を含む請求書で `invoice_received` が重なる | M53 の作るもの 2。請求書と発注の組ごとに `EXISTS` で 1 つにまとめ、単体の準備と壊して落ちる記録を合わせた |
| Claude M54-1・Codex M54-2 | Medium | S4 の審査の経路の期待が新しい形で成り立たず、受注の行ロックで待つことは pid だけでは確かめられない | M54 の完了条件の後の競合テスト。S4 を受注側の取消と計上・審査の承認と計上に、`shipping_lock_spec.rb` を審査の作成と計上・審査の作成と出荷指示の作成・審査の却下と計上に分け、待つ先を `pg_locks` の `relation` で確かめる。受注のロックを外す壊し方は `shipping_lock_spec.rb` で落ちると名指しした |
| Claude M54-3 | Medium | 消す仕組みを前提にした文書の節（`data-model.md` の 2 節・ADR 010 決定 3・4・`testing.md`「行列テストとの分担」）と `git grep` の語に漏れがある | M54 の実装する文書の節と `git grep` の語。`lock_sites_spec.rb` の `Instructions.create` の理由も直すと書いた |
| Claude M54-4 | Medium | 取消済の除外を足す 2 か所の 2 つ目は件数ではなく出荷予定日の並べ替えで、最初に落とす example が当たらない | M54 の作るもの 3 と最初に落とす example と壊して落ちる記録。`instructions_for` と `planned_date` に分けた |
| Claude M53-5 | Low | Bullet は生の `UNION ALL` の繰り返しを捕まえない。並べる場所が決まっていない | M53 の作るもの 2 と単体。SQL の件数で数え、並べるのは Ruby の側と決めた |
| Claude M53-6 | Low | 画面の検査（生成した型・lint・型検査）が完了条件に無い | M53 の完了条件 |
| Claude M54-5 | Low | 表と列を消すマイグレーションの手順が無い | M54 の作るもの 5。前例と同じく `ignored_columns` → `safety_assured`、`down` は空で戻す |
| Claude M54-6 | Low | 出荷指示を残す判断が OI-213 に無い。取消済の受注の指示の取消、`status_sql` に当たらないときの状況、「出荷計上」の受注の項目が決まっていない | M54 の作るもの 3 と範囲外、OI-213 |
| Claude M54-7 | Low | E2E の全体と `spec/scenarios` が完了条件に無い | M54 の完了条件 |
| Codex M54-3 | Low | packwerk の循環の検出の原文が無い | M54 の作るもの 1 |

違和感：前提の表の M54 の行が、テナントをまたぐイベントそのものを同期にすると読める（Claude）。同じファイルから同じテナントへの発行だけを消し、テナントをまたぐイベントは残ると書き直した。Codex の違和感は「なし」だった。

### M53・M54 の読み直し 1

直した版に初回の記録を足した版（`a596fc1`）を、2 系統で読み直した。2 系統とも初回の 15 件の解消を認めた。Codex は新しい指摘を挙げず、M53・M54 とも Go とした。Claude は M53 を Go、M54 を Conditional Go とし、新しい High を 1 件挙げた。High を直し、読み直し 2 に出した。

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Claude R1-M54-1 | High | `lock` が `nil` のときの出荷指示の作成と計上の扱いが決まっていない。出荷の factory は受注の行を作らないので、計上と出荷指示の作成を通す spec と入口の行列の行がこの場合に当たる | M54 の作るもの 3・5。`lock` が `nil` なら何も書かずに `NOT_FOUND`、`mark_shipped` の失敗はセーブポイントまで戻す。`:shipment_request` の factory を同じテナントの受注の行を作る形にし、当たる spec を並べ、落ちた spec と直し方を証跡に書く |
| Claude R1-M53-1 | Medium | `occurred_at` を足したイベントを `new` で作る spec が完了条件の外にある | M53 の作るもの 1 と完了条件。`git grep` で数えて `occurred_at` を渡し、完了条件に `spec/contracts`・`packs/fulfillment/spec`・`packs/billing/spec` を足した |
| Claude R1-M54-2 | Medium | `git grep` の語 `ready_for_shipment` が、残す「出荷可能」のファイルの名前に当たる | M54 の文書に残すこと。項目の読み書き（`ready_for_shipment:`・`.ready_for_shipment`）に限った |
| Claude R1-M54-3 | Medium | 待つ先を `pg_locks` の `relation` で確かめるとき、どの行を見るかが決まっていない | M54 の競合テスト。`locktype = 'tuple'` の行で確かめ、補助を `spec/support/concurrency.rb` に置く |
| Claude R1-M53-2 | Low | `CancellationRequest.decidedAt` の説明が新しい意味と食い違う | M53 の作るもの 3 |
| Claude R1-M54-4 | Low | 置き換えて消す spec の名前が中身と合わない | M54 の競合テスト。`sales_event_receiver_lock_spec.rb` は残す |
| Claude R1-M54-5 | Low | `context-map.md` の図が文書に残すことに無い | M54 の文書に残すこと。あわせて `showcase.md` の受注番号の写しの理由も足した |
| Claude R1-M54-6 | Low | 状況の式に操作者を渡す先の列挙が足りない | M54 の作るもの 3 |

違和感：依存の向きを変えると、出荷の spec の土台（受注の行を作らない factory）の前提も変わることを名指しした方がよい（Claude）。R1-M54-1 の直しで、factory と当たる spec を作るもの 5 に並べた。Codex の違和感は「なし」だった。
