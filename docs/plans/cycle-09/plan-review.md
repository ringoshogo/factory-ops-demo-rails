# サイクル 09 の計画レビュー：M52 と、M33・M41 の残り

この文書は、`implementation-plan.md` の M52 と、M33・M41 の「残り（サイクル 09）」を 2 系統の独立したレビュー（Claude と Codex）にかけ、指摘を計画に反映した記録である。M52 から着手する担当者と、計画をレビューする人が読む。担当者は、計画の節が「なぜこう書いてあるか」をここで引ける。

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
