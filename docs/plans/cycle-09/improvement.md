# サイクル 09 の改善の探索

サイクル 09 の台帳の棚卸しが起動を決めた改善の探索の記録である。手順は `guides/cycle-end.md`「改善の探索」にある。この版は、取りまとめ役の側の調べで、`d8676c2`（再発防止の commit）の版を読み、テーマごとに推奨までを書いた。テーマごとの裁定（`採用`・`監視`・`見送り`）は、2 系統のレビュアーが下の調査を読んで出し、「裁定」の節と改善の候補の台帳に書き足す。

手元では、`TEST_DATABASE=factory_ops_c09end_test` で一時の DB を作り、`d8676c2` の全件（`bundle exec rspec`）と、`spec/platform/ci_checks_spec.rb` と、一時の置き場に写した試作を流した。試作は worktree を書き換えずに、写したファイルを `bundle exec rspec <置き場のパス>` と `-r <置き場のパス>` で読ませた。外部の原文は、GitHub の文書「Evaluate expressions in workflows and actions」（https://docs.github.com/en/actions/reference/workflows-and-actions/expressions ）と、`actions/runner` の main（`594b5cd`、2026-10-16）の式の構文解析のソースを `gh api` で読んだ。

## モード

**検証**。`d8676c2` の台帳で `未着手` は 15 件（サイクル 09 の初め `081a134` では IB-137・IB-138 の 2 件、振り返りの版 `c35a702` では 12 件）。サイクル 09 で足した行は IB-139〜IB-153 の 15 行で、そのうち IB-139・IB-140 は作者の判断で `起票済み` になり、M53・M54 で実装を終えた。回し方に関わる想定外（main の取り込み、読み直しの上限、Codex が spec を流せないこと、`open` の行に判断を書く場所）は再発防止で扱ったので、ここでは扱わない。ただし、逸脱検査の D4 が改善の探索で裁定するとした IB-143 は、下の「ほかの未着手」で推奨を書く。

あわせて、`起票済み` の 4 行（IB-130・IB-134・IB-139・IB-140）の効き目を確かめる。

## テーマと、なぜ今か

優先度は、繰り返した数と続いたサイクルの数、作業を止めるか、費用の小ささ、の順で決めた。

| 優先 | ID | テーマ | なぜ今か | 調べたか |
|---|---|---|---|---|
| 1 | IB-144・IB-141 | `publish` の `if:` の spec を、許す形で照らす。状態の関数の名前の大文字と小文字 | M52 の作るもの 2 に、実装レビューで 3 回続けて High が出た（振り返りの想定外 3）。再発防止は照らし方を選び直すことを改善の探索に送った（`recurrence.md`） | 調べた（手元で試作した） |
| 2 | IB-150 | どの spec も呼ばない公開 API を、全件の流れでは失敗にする | M55 で足したガードが、一部の spec を流すと確かめの外の一覧を 100 を超えて出し、全件では 0 件になる | 調べた（手元で試作した） |
| 3 | IB-145 | 発注の進みの出来事の種類の一覧と GraphQL の enum の一致の検査 | M53 の実装と実装レビューの Codex の違和感 2。足し忘れは実行の時にだけ落ちる | 調べた |
| 4 | IB-142 | `TenantExample.run` より内側の around の送出 | M52 の実装レビューの Claude の違和感 2。OI-214 と同じ系統の穴 | 調べた（該当する around を数えた） |
| 5 | IB-149 | 競合テストのロックの順の確かめ方 | M54 の計画が、待つ先の表の確かめでロックの順の誤りも捕まえる前提で書かれていた（振り返りの想定外 5） | 調べた |
| 6 | IB-130・IB-134・IB-139・IB-140 | `起票済み` の効き目 | IB-130 はサイクル 08 の裁定がサイクル 09 の末に基準 (3) で判定し直すとした。ほかの 3 行は M52〜M54 で実装を終えた | 調べた |
| 7 | IB-137・IB-138・IB-143・IB-146・IB-147・IB-148・IB-153 | 2 サイクル扱わなかった行と、改善の探索の対象に入るかを決める行 | IB-137・IB-138 はサイクル 08 から 2 サイクル目。ほかは回し方・業務の振る舞い・作者の判断に送った行 | 下の表で推奨 |

**扱わなかった件数：2 件**（IB-151・IB-152。このサイクル末の逸脱検査で足した行）。台帳に `未着手` で残り、次の起動の判定の対象になる。

## 起票済みの効き目

台帳の行の判定の記録とサイクル 08 の裁定（`plans/cycle-08/improvement.md`「裁定」）に書いた基準に照らした。基準が台帳に無い行は、起こしたマイルストーンの完了条件と、サイクル 09 の証跡で起きたことに照らした。

| ID | 実装 | 基準 | サイクル 09 の証跡 | 推奨 |
|---|---|---|---|---|
| IB-130 | M51 作るもの 3（M56 で手順を「担当を止めるとき」に寄せた） | (3) サイクル 09 の末に、M51 の後に作った担当とレビュアーの DB だけで、一時の DB の一覧が動いている担当の DB だけで、作者が手で消した回が 0 回 | `d8676c2` で `RAILS_ENV=test bin/rails temp_databases:list` は「一時の DB は無い」を出した（この調べの DB を作る前に流した）。M52〜M55 の担当の DB（`factory_ops_m52_test` など）は一覧に無い。振り返りは「担当の一時の DB の後片付け」を「証跡に記録が無い」とした。作者が手で消した回は、リポジトリの記録からは数えられない | 取りまとめ役が「サイクル 09 の間に作者が手で消した回は 0 回」と確かめられれば `反映済み`。反映先は `guides/config.md`（名前の規則と拒む DB）・`guides/bin.md`（タスクの表）・`guides/dev-cycle.md`「担当を止めるとき」。確かめられなければ `起票済み` のまま、サイクル 10 の末に同じ基準で判定する。一覧が空であることは、誰が消したかを示さないので、判定の記録には「担当を止めるとき」の 2 を誰が流したかも書く |
| IB-134 | M52 作るもの 2 | `publish` の `if:` の spec に、`success()` の否定と論理和を含まない期待がある | 期待は足され、M52 の壊し方の表の 15 の式（否定 2・論理和 1・比べ 5・関数の引数と添字 7）がどれも落ちる（下のテーマ 1 で写した期待を流して確かめた）。ただし、大文字の状態の関数と文字列の中の `success()` を組み合わせた式は通る（テーマ 1） | `反映済み`（足すとした期待の範囲で）。反映先は `guides/config.md`「CI の工程」と `spec/platform/ci_checks_spec.rb`。残った穴は IB-141・IB-144 で扱い、判定の記録にそう書く |
| IB-139 | M53 | 作者の判断（OI-210 の (a)）で起こした行で、基準は無い | M53 を実装し、実装レビューは 2 系統とも Go。逸脱検査の観点 1・3 は、進みの出来事・読む行・時刻・並べ方が `graphql-schema.md`「発注側の視点」と一致するとした。進みの名前と日付の意味のずれは IB-146 に、種類と enum の一致の検査は IB-145 に積んだ | `反映済み`（参考。IB-126 の前例の形）。反映先は `architecture/graphql-schema.md`「発注側の視点」 |
| IB-140 | M54 | 作者の判断（OI-211 の案 2）で起こした行で、基準は無い | M54 を実装し、実装レビューは 2 系統とも Go（High 0 件）。逸脱検査は ADR 012 の依存の向き・ロックの順・イベントの例外が実装と一致するとした。写しを残す理由は作者の判断 OI-226（`blocked-user`）に、取消のロックの順の文は IB-152 に、`ignored_columns` を外す時機は IB-151 に残る | `反映済み`（参考）。反映先は `adr/012-同じテナントの中の連結を同期にし出荷可能だけをイベントで残す.md` と `architecture/context-map.md`「コンテキスト間の関係」。OI-226 の答えで写しを替えるなら、別の行（IB-147）で扱う |

## 調べたテーマ

### 1. IB-144・IB-141 `publish` の `if:` の spec を、許す形で照らす

- **いまの形**：`spec/platform/ci_checks_spec.rb` の 1 つの example が、`publish` の `if:` に 6 つの期待を当てる。小文字の `success()` を含む、小文字の `failure`・`cancelled`・`always` の呼び出しを含まない、`!` を含まない、`||` を含まない、文字列を空にして契機の比べ（`github.event_name == '…'`）を除いた残りが `=`・`<`・`>` を含まない、`success()` を囲む括弧が関数の呼び出しか添字でない（`success_inside_call?`）。`guides/config.md`「CI の工程」（372 行目と 382 行目の段落）、ワークフローの `publish` の前のコメント、spec の example の前のコメント、`showcase.md` の表の行の 4 か所が、落とす迂回の形を並べて書く
- **関数の名前の大文字と小文字**：GitHub の文書「Evaluate expressions in workflows and actions」は、文字列の比べについて「GitHub ignores case when comparing strings.」、状態の関数について「A default status check of `success()` is applied unless you include one of these functions.」と書くが、関数の名前が大文字と小文字を区別するかは書いていない。文書では確かめられなかった。`actions/runner` の `594b5cd` のソースでは、ジョブの `if:` を変換する `WorkflowTemplateConverter.ConvertToIfCondition`（`src/Sdk/WorkflowParser/Conversion/WorkflowTemplateConverter.cs`）が、状態の関数を含むかを `StringComparison.OrdinalIgnoreCase` で `always`・`cancelled`・`failure`・`success` と比べ、含まないときだけ `success() && (…)` にする。関数の表（`src/Sdk/DTExpressions2/Expressions2/ExpressionConstants.cs` の `WellKnownFunctions`）も `StringComparer.OrdinalIgnoreCase` で引く。GitHub の側で同じコードが動くかは確かめていないので、関数の名前は大文字と小文字を区別しない、は推定である（ソースに基づく）
- **手元での確かめ**：いまの 6 つの期待を一時の置き場のスクリプト（`allowed_form_probe.rb`）に写し、許す形と並べて式ごとに照らした。許す形は、`${{ }}` を外し、一部だけの `${{ }}` を拒み、単一引用符の文字列を空にし、外側の余分な括弧を外し、括弧の深さ 0 の `&&` でつないだ項の 1 つが（余分な括弧を外して）大文字と小文字を区別せずにちょうど `success()` であること、とした

  | 式 | いまの期待 | 許す形 | `needs` が落ちたとき |
  |---|---|---|---|
  | M52 の壊し方の表の 15 の式（否定 2・論理和 1・比べ 5・関数の引数と添字 7） | すべて落とす | すべて落とす | 流れる |
  | `success() != false && …`・`always() && … && contains('false', success())` | 落とす | 落とす | 流れる |
  | `${{ 'success()' && Always() }}` | **通す** | 落とす | 流れる（推定。`Always()` が状態の関数に数えられ、`success()` が足されない） |
  | `${{ Always() && github.event_name == 'push' && 'success()' }}` | **通す** | 落とす | 流れる（同上） |
  | `${{ Failure() && 'success()' }}` | **通す** | 落とす | 落ちたときだけ流れる（同上） |
  | `${{ 'x && success() && x' }}` | 通す | 落とす | 止まる（状態の関数を含まないので GitHub が `success()` を足す）。spec の「明示する」には当たらない |
  | 対照：`success() && github.event_name == 'push'`（いまの式）・`${{ github.event_name == 'push' && success() }}`・`(success()) && …`・`… && contains(github.ref, '=')` | 通す | 通す | 止まる |
  | `Success() && …`・`SUCCESS() && …` | 落とす | 通す | 止まる |
  | `success() && always() && …` | 落とす | 通す | 止まる（`success()` との論理積なので偽） |

  いまの期待を通る 3 つの迂回は、小文字だけを見る状態の関数の期待（IB-141）と、`success()` を含むかを文字列を空にする前の式で見る期待の組み合わせで通る。どちらか片方だけでは通らない。M52 の実装レビューの初回と 2 回の読み直しは、どれもこの形を挙げなかった（Claude の違和感 1 が IB-141 として小文字の期待を挙げた）。

  許す形を spec に書いた写し（`ci_checks_allowed_spec.rb`。`publish` の example を許す形の 1 つの期待と、上の式の表を流す example に替えた）は、`d8676c2` のワークフローで 36 examples, 0 failures だった。補助の処理を 1 つずつ外すと、それぞれ表の行が落ちた

  | 壊し方 | 結果 |
  |---|---|
  | 項がちょうど `success()` でなく、`success(` を含めば許す | 17 failures（迂回の行） |
  | 括弧の深さを数えずに `&&` で分ける | 1 failure（`contains('false', github.ref && success() && github.ref) && …`） |
  | 文字列を空にしない | 1 failure（`${{ 'x && success() && x' }}`） |
  | 大文字と小文字を区別する | 1 failure（`Success() && …` を許す行） |
  | 一部だけの `${{ }}` を拒まない | 1 failure（`success() && ${{ github.event_name == 'push' }}`） |

- **比べた形**：(a) いまの期待のまま、`success()` を含むかを文字列を空にした式で見て、状態の関数の期待を大文字と小文字を区別しない形にする（2 行の直し）。(b) 許す形の 1 つの期待に替える。(c) いまのまま
- **合い方**：許す形は、GitHub の式の演算子（文書の表の 12 個）のどれで迂回を作っても、`success()` が深さ 0 の論理積の項である限り `needs` が落ちれば式全体が偽になる、という 1 つの理由で閉じる。いまの期待は、演算子と書き方ごとに落とす形を並べるので、(a) で今回の 3 つを閉じても、次の書き方（GitHub が演算子か関数を足したときなど）で同じことが起きる。許す形は、いまより狭い式を落とさず（対照の 4 つは両方で通る）、`Success()` のような迂回でない式を通す。`failure()` などを `success()` と論理積でつなぐ式も通すが、`needs` が落ちれば偽なので守りは崩れない。書かない理由（読み手を迷わせる）は文書に残せる
- **移す費用**：`spec/platform/ci_checks_spec.rb`（`without_strings` は残し、`success_inside_call?` を約 25 行の許す形の補助に替え、`publish` の example の 6 つの期待を 1 つにし、式の表の example を足す。試作で 134 行 → 162 行）。`guides/config.md`「CI の工程」の 2 つの段落の、迂回の形を並べた文を許す形の 1 文にする。`.github/workflows/ci.yml` の `publish` の前のコメントと、`showcase.md` の表の行（266 行目）を同じ形に直す。`publish` の `if:` そのものは変えない。配線を変えた人の手の確かめ（OI-59）は、`if:` を変えないので要らない
- **効いたとする基準**：(1) M52 の壊し方の表の 15 の式と、上の表の 3 つの迂回が、spec の表の行で落ちる。(2) 補助の処理を 1 つずつ外すと、表の行のどれかが落ちる。(3) `config.md`・ワークフロー・spec・`showcase.md` から、迂回の形を並べた文が消え、許す形の文が `config.md` の 1 か所になる（`git grep -n -F -e "success_inside_call" -- .` と `git grep -n -F -e "format('{0}', success())" -- docs/guides docs/showcase.md .github` が 0 件。いまはそれぞれ spec の 2 件と `config.md` の 1 件）。(4) 次に `publish` の `if:` か照らし方に触れるマイルストーンの実装レビューで、`if:` の迂回の High が出ない
- **推奨**：IB-144 は `採用`（実装を伴う変更）。IB-141 は IB-144 に含めて `見送り`（IB-144 の許す形が大文字と小文字を区別しないので、同じ作業を 2 つの行で追わない。IB-144 を採らないなら、IB-141 を (a) の 2 行の直しで `採用` する）。行き先は、サイクル 10 の最初の小さいマイルストーンの作るものの 1 つ（下のテーマ 2・3 と同じマイルストーンに入れられる大きさ）

### 2. IB-150 どの spec も呼ばない公開 API を、全件の流れでは失敗にする

- **いまの形**：`spec/rails_helper.rb` の `after(:suite)` が、`PublicApiReturns.uncalled`（`before(:suite)` で付けた TracePoint が一度も走らなかった「定数.メソッド」）を `warn` で出すだけで、落とさない。`spec/support/public_api_returns.rb` の冒頭のコメントは、spec を流した範囲で一覧が変わるからとする
- **手元での確かめ**：`d8676c2` の全件は 3150 examples, 0 failures（3 分 27.5 秒）で、一覧は出なかった（呼ばれなかった公開 API は 0 個）。`spec/platform/ci_checks_spec.rb` だけを流すと 146 個が出た
- **全件かどうかを見分ける手段**：
  - rspec に自分で判定させる形：rspec-core 3.13.6 の `RSpec::Core::Configuration` は、渡されたパスの読み手（`files_or_directories_to_run`）を公開していない（呼ぶと `NoMethodError`）。インスタンス変数を読む試作（`full_run_probe.rb`、`--dry-run`）では、引数なしの全件は既定の `spec` と `packs/*/spec` の 10 個のパス・188 ファイル・3150 examples、`-e` は同じ 10 個のパスのまま `full_description` の絞り込みを足し、`path:line` は `locations` の絞り込みを足した。全件と言うには、パスが既定であること、絞り込み（`-e`・`--tag`・`:focus`・行の指定）が無いこと、`--only-failures` でないことを、公開されていない状態から組み合わせて読むことになる
  - 全件の流れに印を渡す形：全件を流すのは `config/ci.rb` の「Tests: RSpec」と、ワークフローの `test` のジョブの「Run tests」の 2 か所で、どちらもすでに `COVERAGE=1` を渡している。専用の環境変数（たとえば `PUBLIC_API_RETURNS_FULL=1`）を 2 か所に足し、`after(:suite)` がその印のあるときだけ例外にする。試作（`uncalled_fail_probe.rb`）で、印を付けて 1 ファイルを流すと「An error occurred in an `after(:suite)` hook.」「8 examples, 0 failures, 1 error occurred outside of examples」で終了コード 1、印なしで 0 になった
- **合い方**：印を渡す形は、rspec の内部に依らず、印の無い手元の一部の実行の出力を変えない。`COVERAGE=1` を印に兼ねると、分岐の計測と別の意味を同じ変数に持たせるので、専用の変数にする。2 か所の片方で印を書き忘れると黙って緩むので、`ci_checks_spec.rb` に、2 か所の RSpec のステップが印を渡すことの期待を足す（同じ spec がコマンドの名前を 2 か所で照らす形と同じ）。分岐の網羅率の警告は Ruby の分岐しか拾わず、分岐の無い公開 API が spec に呼ばれないことは、いまどの検査も落とさない
- **移す費用**：`spec/rails_helper.rb` の `after(:suite)`（約 3 行）と、判定を `PublicApiReturns` の 1 つのメソッドに寄せてその example を `spec/platform/public_api_returns_spec.rb` に足す。`config/ci.rb` の RSpec のステップと `.github/workflows/ci.yml` の「Run tests」の `env` に印を足し、`ci_checks_spec.rb` に印の期待を足す。`public_api_returns.rb` の冒頭のコメントと、`guides/packs-and-packwerk.md`「公開 API を出す」の返す値の箇条と `guides/config.md`「CI の工程」に、全件では落とすことを書く。いま全件で 0 個なので、入れたときに直す spec は無い
- **効いたとする基準**：(1) どの spec も呼ばない公開の特異メソッドを 1 つ足すと、`bin/ci` と CI の `test` のジョブが落ち、印の無い `bundle exec rspec <1 ファイル>` は落ちない。(2) 2 か所のどちらかから印を外すと `ci_checks_spec.rb` が落ちる。(3) 入れた後のサイクルで、全件が呼ばれなかった公開 API で落ちたら、その PR で spec を足したことが証跡にある
- **推奨**：`採用`（実装を伴う変更）。行き先はテーマ 1 と同じ小さいマイルストーン

### 3. IB-145 発注の進みの出来事の種類の一覧と GraphQL の enum の一致の検査

- **いまの形**：進みの出来事の種類は `Purchasing::PurchaseOrderTimeline::KINDS`（`packs/purchasing/app/models/`、10 個）が並べ方の順も持ち、`Types::PurchaseOrderTimelineKindType` が同じ 10 個を同じ順に書く。画面の名前（`PURCHASE_ORDER_TIMELINE_LABEL`）は codegen の型で enum とそろう。公開 API と enum の間の一致を確かめる example は無い。`spec/requests/purchase_orders_spec.rb` の進みの example は、`ORDERED`・`ACCEPTED`・`SHIPPED` の 3 つの種類だけを GraphQL で読む。種類を公開 API に足して enum に足し忘れると、その種類を持つ発注の詳細の問い合わせだけが、実行の時に `GraphQL::Schema::Enum::UnresolvedValueError`（graphql-ruby 2.6.11）で落ちる
- **同じ形の状況の検査**：内部の一覧と GraphQL の enum の組を数えた

  | 組 | 一致の検査 |
  |---|---|
  | 進みの種類（`PurchaseOrderTimeline::KINDS` と `PurchaseOrderTimelineKindType`） | 無い |
  | 発注の状況（`PurchaseOrderStatus::ALL` と `PurchaseOrderStatusType`） | 無い。`spec/scenarios/demo_world_spec.rb` が、E2E の世界の発注の状況が enum の値（`sent` を除く）ちょうどであることを確かめるので、enum にだけある値は落ちるが、公開 API にだけ足した値は、世界がその状況の発注を作らない限り落ちない |
  | 受注の状況（`SalesOrderStatus::ALL` と `SalesOrderStatusType`） | ある。`spec/requests/dashboard_spec.rb` が、`count_by_status`（`ALL` から作る）のキーと enum の値の一致を確かめる |
  | 出荷依頼の状況（`ShipmentRequestStatus::ALL` と `ShipmentRequestStatusType`） | 発注の状況と同じく、E2E の世界の example だけ |

  `bin/rails runner` で 4 つの組を比べると、どれも値と順まで一致した（10・7・7・5 個）
- **合い方**：内部の一覧は各パッケージの `app/models/` にあり、`enforce_privacy: strict` なので、ルートの spec からは読めない。パッケージの spec は、パッケージがルートに依存しないので `Types::` を読めない。一致を確かめるには、(a) 一覧を公開 API の定数として出し（`Inventory::Adjustment::TYPES` などの前例がある）、ルートの spec（`spec/graphql/`）で enum の値と順まで比べる、(b) enum の値を公開 API の定数から作り、名前の表に無い値があれば読み込みで落とす、のどちらかになる。(a) は検査だけを足し、enum の説明（日本語の名前）を今の置き場に残す
- **移す費用**（(a)）：`Purchasing::PurchaseOrders` に進みの種類と発注の状況の定数、`Fulfillment::ShipmentRequests` に出荷依頼の状況の定数を足し（各 1 行）、`spec/graphql/` に 3 つの組を比べる spec（約 20 行）を足す。受注の状況は `dashboard_spec.rb` があるので足さなくてよい。公開 API の戻り値のガードは定数を対象にしないので、IB-150 に当たらない
- **効いたとする基準**：内部の一覧に値を 1 つ足す、enum から値を 1 つ消す、enum の値の順を入れ替える、の 3 つの壊し方で、それぞれ足した spec が落ちる
- **推奨**：`採用`（実装を伴う変更）。行き先はテーマ 1 と同じ小さいマイルストーン。順まで比べるかは、進みの種類の順が並べ方（`RANKS`）を決め、enum の順が画面の凡例の順にならないかをそのマイルストーンの計画で決める

### 4. IB-142 `TenantExample.run` より内側の around の送出

- **いまの形**：`TenantExample.run` を呼ぶ around は、19 ファイルに 20 個ある（M52 で書き換えた 18 個と、M55 で足した `spec/platform/public_api_returns_spec.rb`・`packs/platform/spec/models/sql_subquery_spec.rb`。`spec/platform/tenant_example_spec.rb` の中の内側の group を除く）
- **数えたこと**：この 19 ファイルで、`TenantExample.run` の around を持つ group の内側の group に around を書いた箇所は 0 個だった。`packs/inventory/spec/public/inventory/adjustment_spec.rb` の 2 つは別の最上位の `describe` にある。共有の文脈「RLS の SELECT と UPDATE を開く」（`spec/support/cross_read.rb`）は around を持たない。`packs/sales/spec/public/sales/item_prices_spec.rb` の around は、`TenantExample.run` の前に `foreign` を呼ぶので、送出するなら `example.run` の前で、OI-214 の範囲である
- **合い方**：内側の around が無いので、穴は今どの example にも当たらない。足す人が `TenantExample.run` の内側に around を書いたときだけ当たる。`tenant_example_spec.rb` のガードは、`Tenancy.with_tenant` かトランザクションで example を直に包む around を字面で探しているので、同じガードに「`TenantExample.run` の around を持つファイルの、内側の group の around」を数える期待を足せば、最初の 1 つで捕まえられる（約 10 行）。いまは対象が 0 個なので、壊して落ちる対照を作るには合成のソースが要る
- **推奨**：`見送り`。調べ直す条件：`TenantExample.run` の around を持つ group の内側に around を足すとき、または around を持つ共有の文脈をその group で読むとき（そのマイルストーンで、ガードに内側の around の期待を足す）

### 5. IB-149 競合テストのロックの順の確かめ方

- **いまの形**：`guides/testing.md`「競合テスト」の手順 3 は、どの表の行を待つかまで確かめるとき（同じ操作が順の違う 2 つの行ロックを取り、どちらで待つかが仕様のとき）に `waiting_row_tables` を使うと書く。待ち終えて行ロックを得た接続はタプルのロックを手放すので、補助は「どこで待っているか」は読めるが「どの順に取ったか」は読めない。ロックの順は、1 本の接続で流れた `FOR UPDATE` の SQL の順を確かめる example（`packs/fulfillment/spec/public/fulfillment/shipping_spec.rb` の「ロックを受注 → 出荷依頼 → 出荷指示 → 在庫 → 引当の順に取る」と、M54 の Codex R2 で足した出荷指示の作成の順の example）だけが守る
- **起きたこと**：M54 の計画の競合テストの文は、待つ先の確かめで順の誤りも捕まえる前提で書かれ、実装レビューの Claude の違和感 2 が、出荷依頼と受注の順の入れ替えを捕まえないと挙げた（振り返りの想定外 5）。順の誤りは、実装レビューの Codex R2（出荷指示の作成のロックの順の example が無い）で example を足して閉じた
- **合い方**：書き足すのは手順 3 の 1 文で、「`waiting_row_tables` は待つ行の表を読み、ロックを取った順は読まない。順を守るときは、1 本の接続で流れた SQL のロックの順を確かめる example を書く」の形になる。規則そのものは新しくないが、計画を書く者が補助の名前から順の確かめを期待した事例が 1 回あった
- **移す費用**：`guides/testing.md` の 1〜2 文。コードと spec は変えない
- **効いたとする基準**：次にロックの順を足すか変えるマイルストーン（`spec/db/lock_sites_spec.rb` の表に行を足すもの）の計画の壊して落ちる記録の表に、順を入れ替える壊し方と、落ちる example として SQL の順の example が書かれ、実装レビューに「順の入れ替えを捕まえない」の指摘が出ない
- **推奨**：`採用`（規則の変更）。`試行中` にし、判定するマイルストーンは、サイクル 10 以降で最初にロックを取るメソッドを足すか順を変えるマイルストーンとする。サイクル 10 にそのマイルストーンが無ければ、サイクル 10 の末に「判定の対象なし」と書いて `試行中` のまま次へ送る

## ほかの未着手

サイクル 09 の証跡と計画に、IB-137・IB-138 を新しく挙げた箇所は無い。

| ID | 推奨 | 理由と調べ直す条件 |
|---|---|---|
| IB-137 | 見送り | 2 サイクル扱わなかった行。`frontend/lib/format.ts` の冒頭の説明は「数値と金額の表示」のままで、`isCancelled` と `TotalStatus` は M33 の残りの形から変わっていない。振る舞いに影響せず、名前の取り違えによる指摘は出ていない。条件：`format.ts` か `statuses.ts` に状況の判定を足すとき（そのマイルストーンで置き場と名前を合わせる） |
| IB-138 | 見送り | 2 サイクル扱わなかった行。説明の対象の `spec/support/around_hook_errors.rb` は M52 で消え（`git grep around_hook_errors` は `docs/plans/` と `implementation-plan.md` のほかに 0 件）、around の規則は `guides/testing.md`「層への配分」の、行列でない spec を書く人が読む節に `TenantExample.run` として書かれた。行の前提が無くなった。調べ直す条件は持たない |
| IB-143 | 見送り（対象外） | 回し方で、改善の探索の対象（設計と実装のやり方）に入らない。答えは OI-221 と M56 の節に出て、再発防止が `guides/dev-cycle.md`「3. サイクル末」に、サイクル末のブランチを `origin/main` の先端から切ることと、担当に main を取り込ませる計画にしないことを足した（振り返りの改善の提案 1）。条件：サイクル末のブランチが main の先端を祖先に持たないまま、次のサイクルの計画を書いたとき |
| IB-153 | 見送り（対象外） | 回し方。`dev-cycle.md`「担当を止めるとき」は、担当が報告の前に自分のサブエージェントが止まったことを確かめて報告に書く形で、2 の削除が接続の残りで失敗したときは接続を持つプロセスを止めてから流し直す手順もある。条件：残ったサブエージェントの接続で一時の DB を消せなかった事例が出たとき |
| IB-146 | 見送り（対象外） | 進みの「請求書の受領」を受け取った日で並べるか名前を変えるかは、画面に出す業務の言葉と日付の意味で、作者の判断に当たる。改善の探索では扱わず、作者への一覧に載せる候補として台帳の棚卸しへ送る |
| IB-147 | 見送り（作者の判断へ） | 写しを副問い合わせに替えるかは、作者の判断 OI-226（`blocked-user`、引当先 M54）の (b) と同じ問い。同じ作業を 2 つの台帳で追わない。OI-226 の答えが (b) なら、その答えでマイルストーンを起こす |
| IB-148 | 見送り（作者の判断へ） | 逸脱検査の D7 で OI-226 にまとめた。IB-147 と同じ |
| IB-151・IB-152 | 扱わなかった | このサイクル末の逸脱検査で足した行。次の起動の判定の対象になる |

## 回し方の点検

| 指標 | 読み取れること |
|---|---|
| 再発 | (1) サイクル 08 で足した「計画の節に書き足した決めも `judgment` で登録する」：M52 の後始末の形（`99545f4`）で再発した（逸脱検査の D2）。2 サイクル続いたので、再発防止は `bin/check-open-items` の検査にした。(2) サイクル 08 の想定外 10（積み重ねた PR が main を取り込まない）：サイクル 08 の再発防止は仕組みを足しておらず、サイクル 09 の想定外 2 で再び出た。今回は `dev-cycle.md`「3. サイクル末」を直した。計画が main の変更と同じ節を書き換えるかは機械で判定できないので文書のまま（`recurrence.md`）。(3) Codex が spec を流さない：サイクル 08 と 2 回目（想定外 6）。環境の制約で、文書を直した。(4) サイクル 08 の改善の探索で足した「原因を観測で確かめてから形を比べる」：今回のテーマに落ち方や止まりを取り除くものは無く、当てる対象が無かった。IB-144 は、推定ではなく式を流して比べた |
| レビューの漏れ | 逸脱検査で見つかったもののうち、実装レビューの観点に当たるもの：D2（M52 の `judgment` の欠け。観点「計画への準拠と範囲」）と D5（`config.md` の照らし方の文と spec の食い違い。観点「参照の維持」）は、M52 の実装レビューの初回と 2 回の読み直しのどれも挙げなかった。D1 は M56 の実装レビューも挙げた。作者の監査（OI-218）は、OI-215・OI-216・OI-211 が計画レビュー・実装レビュー・逸脱検査をすり抜けたとし、M55 の作るもの 4 が層ごとの責務を 3 つの観点から名指しした。この調べで、M52 の初回と 2 回の読み直しを通った `publish` の `if:` の期待に、大文字の状態の関数と文字列の中の `success()` を組み合わせた迂回（推定）が残っていた（テーマ 1）。Claude の違和感 1 は小文字の期待を挙げていたが、指摘ではなく違和感として改善の候補に送られた。読み直しの上限に当たった守りでは、違和感の扱いが穴を残しうる |
| 正本の太り方 | `git -c core.quotepath=off diff --numstat 081a134..d8676c2 -- docs/architecture docs/adr docs/guides` で、14 ファイル・+305／−123 行（純増 182 行）。マイルストーンの範囲（`git diff --shortstat 081a134..c35a702 -- docs/architecture docs/adr docs/guides`）で +280／−108 行、サイクル末（`c35a702..d8676c2`）で +27／−17 行。増えたのは、ADR 012 の新設（+84 行）、`graphql-schema.md`（+79／−13 行。M53 の進み）、`context-map.md`・`data-model.md`（+35／−30 行、+35／−35 行。M54 の同期化）、`packs-and-packwerk.md`（+17／−1 行。M55 の層ごとの責務）、`dev-cycle.md`（+24／−14 行。M56 と再発防止）。サイクル 08（純増 8 行）、サイクル 07（35 行）、サイクル 06（116 行）より大きく、マイルストーンが 3 つから 6 つに増え、業務の形を変える M54 を含んだことによる。減らした行は書き換えで、棚卸しで削った行ではない。下の正本の棚卸しで、重複を減らす候補を挙げる |
| 攻めの発火 | `未着手` は、サイクル 09 の初め 2 件 → 振り返りの版 12 件 → `d8676c2` で 15 件。IB-137・IB-138 は 2 サイクル `未着手` のまま残った（上の表で見送りを推す）。改善の探索は 4 サイクル続けて「検証」で起動した。台帳に毎サイクル 10 行を超える行が積まれており、発見のモードに切り替える根拠は無い |

## 違和感（調査）

- 台帳の IB-141 の「なぜ今か」は「区別するかは確かめていない」とするが、GitHub の文書は関数の名前の大小を書いておらず、文書だけでは確かめられない。判定の記録には、`actions/runner` のソースに基づく推定であることを書く
- IB-134 の基準（否定と論理和を含まない）は満たしたが、守りたいこと（`needs` が落ちたら `publish` が流れない）は、大文字の状態の関数と文字列の中の `success()` の組み合わせで満たしていない（推定）。基準を守りたいことではなく足す期待で書いたので、基準を満たしても穴が残った。サイクル 08 の裁定の違和感（`反映済み` が実装を伴う行の部分的な達成を見落としうる）と同じ向きで、判定の記録に「足した期待の範囲で」と書く
- IB-130 の基準 (3) の「作者が手で消した回が 0 回」は、リポジトリの記録から数えられず、取りまとめ役の観察に頼る。振り返りの成果物の表も「証跡に記録が無い」とした。一覧が空であることは、誰が消したかを示さない
- `config.md` の 382 行目の段落は「YAML の式を文字列で照らす spec は、式の書き換えに追従できない」を理由に式を照らさないとしつつ、`publish` の `if:` を例外として照らす。IB-144 を採るなら、例外の文を「許す形を 1 つ決めて照らす」に替え、追従できない理由が当たらないことを書く

## 正本の棚卸し

正本（`architecture/`・`adr/`・`guides/`、`showcase.md`）を、参照先が消えた記述・同じことを書いた記述・1 つのマイルストーンでしか使われなかった記述の 3 つで読み直した。削る記述とまとめる記述の提案は次のとおりで、どれも裁定の後に PR にまとめて作者のマージを承認とする。

| 見たこと | 結果と提案 |
|---|---|
| 参照先が消えた記述 | 節の参照は `spec/rubocop/section_references_spec.rb` を含む全件が通った（3150 examples, 0 failures）。M52・M54 で消した補助・表・例外（`around_hook_errors`・`shipping_holds`・`NotShippedYet`）は、`git grep -c -e shipping_holds -e NotShippedYet -e around_hook_errors -- docs/architecture docs/adr docs/guides docs/showcase.md README.md` で 0 件だった。IB-138 の対象（`around_hook_errors.rb` の説明の置き場）は、ファイルごと消えた |
| 同じことを書いた記述 | `publish` の `if:` の迂回の形を並べた文が、`guides/config.md`「CI の工程」の 2 つの段落、`.github/workflows/ci.yml` の `publish` の前のコメント、`spec/platform/ci_checks_spec.rb` の example の前のコメント、`showcase.md` の表の行の 4 か所にある。M52 の読み直しのたびに 4 か所を直した（`0334a68` も `config.md` と `showcase.md` を直した）。IB-144 を採るなら、許す形の文を `config.md` の 1 か所に置き、ほかは参照にする。採らなくても、ワークフローと spec のコメントの迂回の列挙は `config.md` を指す形にまとめられる |
| 同じことを書いた記述 | 一時の DB と担当を止める手順は、M56 と `0334a68` で `dev-cycle.md`「担当を止めるとき」の 1 か所と参照になった。タスクの仕様（名前の規則・拒む DB・`FORCE` なし）は `config.md` と `bin.md` に残り、読む目的が違うので残す |
| 1 つのマイルストーンでしか使われなかった記述 | 無し。`testing.md` の `waiting_row_tables` の箇条は M54 の競合テストでしか使われていないが、ロックを取るメソッドを足す人がこれからも読む手順の一部なので残す（テーマ 5 で、読めないことを足す） |
| 決定の理由が成り立たなくなった記述 | ADR 011 の代替案 D は、退けた理由が ADR 012 で成り立たなくなったと書き足してある。写しを残すか替えるかは OI-226 の作者の答えを待つので、棚卸しでは触れない |
