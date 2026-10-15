# サイクル 8 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M51 手元の検証を止めるものを取り除く：E2E のログインの待ち、一時の DB の後片付け、RLS を開くグループの止まり

`m51-local-checks`（base は `main`）。サイクル 08 の計画の `cycle-08-plan` の先端 `89fd27e` から切った。計画の PR #91 が未マージの間は、その commit も PR の差分に見える。M51 の差分は `89fd27e..` である。

Codex も Claude も Go だった。どちらの系統も、`89fd27e..63dc088` の diff を `63dc088` を展開したディレクトリと `git show` で読んだ。Claude は spec を流さず、rspec-rails 8.0.4 の原文と証跡を読んだ。Codex は、手元の DB への接続が実行の環境で許されず（`Operation not permitted`）、DB を使う spec と E2E を流さず、`ci_checks_spec.rb` を Rails を読み込まない形で、`TempDatabases` の名前の判定と `MatrixCrossRead` の診断の失敗を代わりのオブジェクトで、`AroundHookErrors` の `skip` を rspec-rails の原文の around と数えるだけのフックで、メモリの上で流した。Codex は結果のファイルを読み取りだけの制約で書けず、標準出力に出したので、そこから写した。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High 以上が無かったので、読み直しには出していない。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Go（Medium 2・Low 2） | 出していない（High が無かった） |
| Claude | Go（Medium 2・Low 2） | 出していない（同上） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R3） | 指摘（R1） |
| 正しさ | 指摘（R1） | 指摘なし |
| 境界と規約 | 指摘なし | 指摘（R3・R4） |
| テストの検出力 | 指摘（R1・R2） | 指摘なし |
| 参照の維持 | 指摘（R4） | 指摘（R2） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | R1：`AroundHookErrors` が `skip` を送り返すので、around の中で `example.run` の前か後に `skip` すると、rspec-rails の巻き戻しが飛ぶ | `skip` は呼んだ時点で example を pending にしてあるので、送り返さずに巻き戻しへ戻す形にした。`around_hook_errors_spec.rb` に、前と後で `skip` した 2 つの example の後に、アプリと所有ロールの接続にトランザクションが残らない example を足した（直す前は `got: [2, 2]` で落ちた） | この節を載せた commit |
| Medium | Codex | R2：打ち切った後の診断が失敗したときの守り（`lock_holders` と `activity` の rescue、`activity` のセーブポイント）を確かめる example が無い | `cross_read_spec.rb` に 2 つの example を足した。状態を引く問い合わせと `pg_locks` を引く問い合わせを、それぞれ SQL のエラーになる文に差し替え、引けなかったと出ること、打ち切りの例外が `cause` に残ること、呼んだスレッドのトランザクションがその後も使えることを確かめる。下の壊して落ちる記録に、rescue とセーブポイントを外す行を足した | 同上 |
| Medium | Claude | R1：ログインの待ちの値を、計画が判定に使わないとした負荷のある手元の数字で決めたのに、「計画との違い」に無い | 「計画との違い」と計画の作るもの 2 に、比べからは値が決まらなかったことと、20 秒にした材料を書いた。「E2E」の「判定に使っていない」を、採った形の受け入れに使っていないという意味に書き分けた | 同上 |
| Medium | Claude | R2：`guides/packs-and-packwerk.md` が `test.rb` の `eager_load` の前の式を引き、「手元では使うまで気づかず」と書く | 手元の rspec では気づかず、CI と手元の E2E の起動の時の読み込みで落ちる形に直し、式は `config.md`「環境ごとの設定」を指した | 同上 |
| Low | Codex | R3：E2E の比べの表が待ち 5 秒の回だけで、20 秒を採った 3 回に最初のログインの時間が無い。高負荷の数字の扱いの文が食い違って読める | Claude R1 と同じく直した。採った 3 回は計測を外した版で流したので、最初のログインの時間は無い。待ちの値は時間切れの上限だけを変え、通る回のログインの時間を変えない | 同上 |
| Low | Codex | R4：`Resolvers::SortArguments` のコメントと `catalog_spec.rb`（request）の example の名前が「`orderBy` を省いた `thenBy`」をエラーにすると書き、空の配列を区別しない。`packs-and-packwerk.md` は Claude R2 と同じ | どちらも「空でない `thenBy`」に直した | 同上 |
| Low | Claude | R3：`cross_read_spec.rb` の describe のブロックの中の定数 `DIRECT_REMOVE_EXAMPLE`・`WAIT_SECONDS` が `Object` の定数になる | `WAIT_SECONDS` は `ConcurrencyHelpers::WAIT_SECONDS` を返すメソッドにした。名指しの example の定数は Prism の判定が名前を見るので残し、`MATRIX_CROSS_READ_DIRECT_REMOVE_EXAMPLE` に改め、最上位の定数になることをコメントに書いた | 同上 |
| Low | Claude | R4：`AroundHookErrors` が依存する rspec-core の include の順の出典がコメントに無い | rspec-core 3.13.6 の `ExampleGroup.subclass` が本文の `module_exec` の前に `set_it_up` から `Configuration#configure_group` を呼ぶことを引いた | 同上 |

違和感は次のように扱った。

- Claude 1：`publish` の `if:` の spec が、`success()` の否定と論理和でつないだ形を通す → IB-134
- Claude 2：E2E の比べの表に A1〜A3 が無い → 数えなかった回の理由を「E2E」に書いた
- Claude 3：`TempDatabases` がそのときの `TEST_DATABASE` の DB を拒まない → IB-135
- Claude 4：around が `example.run` の前に `skip` すると巻き戻しが飛ぶ → Codex R1 と同じく直した
- Codex 1：`E2E_EAGER_LOAD` を外しても落ちる example が無い → 計画レビューで積んだ IB-131 のまま
- Codex 2：`AroundHookErrors` が拾う例外の範囲の境目を固定する spec が無い → IB-136

### 実装の記録

#### 計画との違い

- 作るもの 5 の止まりは、計画の前提（所有ロールの接続が表のロックを待つ）と違う形だった。M50 の壊し方で `packs/sales/spec/public/sales/catalog_spec.rb` を丸ごと流し、止まった状態（7 分を過ぎても終わらなかった）で `pg_stat_activity`・`pg_locks` を引くと、所有ロールの接続が `idle in transaction` のまま 41 の全テナントの表の `AccessExclusiveLock` を持ち、アプリのロールの接続が `items` への INSERT（後ろのグループの世界の作成）で `Lock`／`relation` を待っていた。所有ロールは何も待っておらず、`lock_timeout` では終わらない。原因は、落ちた example を包む `around { Tenancy.with_tenant(supplier.id) { example.run } }` だった。example の `PG::CardinalityViolation` を rspec が `example.run` の中で拾うので、`with_tenant` はそのままセーブポイントを解放しようとして `PG::InFailedSqlTransaction` を around から送出する。rspec-rails は example ごとのトランザクションの巻き戻しを、さらに外側の around の `after_teardown` で `ensure` なしに行う（rspec-rails 8.0.4 の `lib/rspec/rails/adapters.rb` の `MinitestLifecycleAdapter`）ので、送出で巻き戻しが飛び、トランザクションがアプリと所有ロールの両方の接続に残った。example の後のフックで数えると、落ちた example の後から、開いたトランザクションの段がアプリの接続で 2 から 3 に、所有ロールの接続で 1 から 2 に増え、後ろのグループの `add!` は所有ロールの接続の 1 段の残りの中で流れた（コミットされない）。取りまとめ役に返し（`../../guides/dev-cycle.md`「前提が崩れたとき」）、判断 D-1 を受けて、次の 2 つを足した（`d25b9f1`）。
  - `MatrixCrossRead.add!`・`remove!` は、所有ロールの接続にトランザクションが残っていれば、足し外しをせずに理由を出して失敗する（補助の中の直し）
  - `spec/support/around_hook_errors.rb` を `rails_helper.rb` で rspec-rails の後に include し、rspec-rails の around の内側、group の本文の around の外側で、around の送出を example の失敗に移して巻き戻させる（根本の直し）。spec の補助で直せたので、D-1 のとおり M51 に入れた。本番の `Tenancy` は変えていない
  計画の作るもの 5・完了条件・範囲外の節は、`56bc85f` で直した。補助の直しを入れた `d25b9f1` と同じ commit で直さなかった。
- `remove!` の打ち切りの example で、補助の直しの example からは `remove!` を呼ばず、`add!` だけで確かめた。2 つは同じ所有ロールの接続の取り方（`with_owner_connection`）を通り、`remove!` を直に呼べるのは計画で名指しした 1 つの example だけだからである。
- 計画の外で、打ち切りの example に、`add!` を呼んだスレッドの接続がロックを持つ形（「このスレッドの接続」と出す）の example を足した。計画は、その pid の状態を引かずに「このスレッドの接続」と書くとしたが、確かめる example が無かった。
- 直の呼び出しを止める example は、名指しの example の中を外す判定を、合成したソースの 3 つ（名指しの example の中・同じファイルのほかの example・ほかのファイル）でも確かめる。外す判定をファイル全体に広げる壊し方で、最初は何も落ちなかったからである（下の B8）。
- ログインの待ちの値（作るもの 2）は、計画の比べでは決まらず、計画が判定に使わないとした負荷のある手元の数字から決めた。負荷の低い手元の 4 回（A4・B1・A5・B2）はどれも待ちが 5 秒で、各ワーカーの最初のログインは `eager_load` の有無によらず 1 秒未満で、5 秒で落ちなかった。待ちの値を替えて流しても、負荷の低い手元では最初のログインの時間は変わらないので、比べからは値が決まらない。20 秒は、負荷のある手元でボタンを押してから時間切れまでが 15.5 秒に達した回と、IB-117 の記録（時間切れの前の 2 件のテストに 10 秒と 17 秒）から決めた。この期待はログインが済んだことを確かめるだけで、延ばしても製品の遅さを隠さない。計画の作るもの 2 に、この決め方を書いた。下の「E2E」の「判定に使っていない」は、採った形の受け入れ（3 回続けて通ること）に使っていないという意味である
- 一時の DB の削除のタスクは、`temp_databases:drop[名前]` の形にした。zsh は角括弧を展開するので、手順の文書では引用符で囲んだ。
- 打ち切ったときのメッセージに、計画の 5 つ（pid・ロール・状態・トランザクションの開始の時刻・対象の表）に加えて、その接続の最後の問い合わせ（200 文字まで）を出した。どの spec がトランザクションを開いたかをたどるためである。
- 「同じ名前のポリシーがすでにある」の失敗のメッセージの外し方を、`MatrixCrossRead.remove!` から、打ち切りのメッセージと同じコマンドに替えた。`guides/testing.md`「行列テストとの分担」の手で外すコマンドも同じ形に直した。
- 前の形（「状態の関数を書かない」「暗黙の `success()`」）は、`git grep` で、`ci.yml` のコメントの「GitHub は状態の関数を含まない if: にだけ success() を足す」（いまの形の説明）、`handoff.md`「リポジトリの状態」の M48 の要約、計画の M48・M51 の節、証跡のほかに 0 件である。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）は、作るものごとに、実装を変える前に流した。どれも `TEST_DATABASE=factory_ops_m51_test` で、Ruby 3.4.11・PostgreSQL 18 で流した。

- 作るもの 4（`89fd27e` の作業ツリーに spec だけを足して。7 examples, 3 failures）：`add!` の example と `remove!` の example が `expect(thread.join(WAIT_SECONDS)).not_to be_nil` で `expected: not nil got: nil`（10 秒で終わらない）。直の呼び出しを止める example が `expected: [] got: ["spec/matrix/cross_read_spec.rb"]`（名指しの例外がまだ無い）。どちらも、`ensure` の後片付けで待っている所有ロールの接続を終わらせ、ポリシーは残らなかった（後ろの example が通った）
- 作るもの 4 の補助の直し（D-1。9 examples, 2 failures）：`add!` が `expected Exception with message matching /所有ロールの接続にトランザクションが残っている/ but nothing was raised`。もう 1 件は、この example が `remove!` も直に呼んでいたので、直の呼び出しを止める example が落ちた。`remove!` の呼び出しを外した（上の「計画との違い」）
- 作るもの 5 の根本の直し（D-1。1 example, 1 failure）：`spec/platform/around_hook_errors_spec.rb` が、落ちた example の次の example の中の開いたトランザクションの段で `expected: [[2, 1]] got: [[3, 2]]`
- 作るもの 3（`lib/temp_databases.rb` を、一時の DB と判定しない・一覧が空・削除が何もしない形の空の実装にして。4 examples, 4 failures）：`temporary?` が `got: []`、一覧が `expected {} to include {"factory_ops_spec4a59c13d_test" => 0}`、接続中の削除が `expected PG::ObjectInUse … but nothing was raised`、拒む削除が `got: [:dropped, … ×8]`
- 作るもの 7（`ci.yml` を変える前に。8 examples, 1 failure）：`expected "github.event_name == 'push'" to match /\bsuccess\s*\(\s*\)/`
- 作るもの 6：足した example は、書いた時点の検証で通る見込みだった。最初の版は省いたときの並びの期待を誤り（`B-1` が先）、`expected … got: [{"code" => "A-1"}, {"code" => "B-1"}]` で落ちたので、期待を応答に合わせた。これは RED に数えず、下の壊して落ちる記録で RED に代える

壊して落ちる記録は、壊すファイルを一時ファイルの置き場に複製してから壊し、spec を流して、複製から戻した。

| 確かめる example | 壊したもの | 落ちたもの |
|---|---|---|
| `cross_read_spec.rb` の `add!` の打ち切り | `add!` のときだけ `SET LOCAL lock_timeout` を流さない（B1） | 2（この example と、このスレッドの接続の example。10 秒で終わらない） |
| `cross_read_spec.rb` の `remove!` の打ち切り | `remove!` のときだけ `SET LOCAL lock_timeout` を流さない（B2） | 1（この example） |
| 〃 | 外すコマンドの `TEST_DATABASE` を消す（B5） | 1（同上） |
| 〃 | ポリシーが残ったことと外すコマンドの文を消す（B6） | 1（同上） |
| 打ち切りの 3 つの example | ロックを持つ接続を引かず「不明」と出す（B3） | 3 |
| `cross_read_spec.rb` のこのスレッドの接続 | pid を比べずに状態を引く（B4） | 1（この example） |
| 直の呼び出しを止める example | 同じファイルのほかの example に `MatrixCrossRead.remove! if false` を足す（B7） | 1（この example） |
| 〃 | 名指しの example の判定を、このファイル全体を外す形にする（B8） | 最初は 0。合成したソースの確かめを足した後に 1 |
| 〃 | 名指しの example も外さない（B9） | 1（この example） |
| `cross_read_spec.rb` の補助の直し | 所有ロールの接続のトランザクションの確かめを外す（`if false &&`） | 1（この example） |
| `around_hook_errors_spec.rb` | `rails_helper.rb` の `config.include AroundHookErrors` を外す | 1（`got: [[3, 2]]`） |
| 〃 | 送出を example の失敗に移さずに飲み込む | 1（around の送出が失敗の文に出ない） |
| `temp_databases_spec.rb` の名前の規則 | 既定の 3 つの除外を外す | 3（名前の規則・一覧・拒む削除） |
| 〃 | `_` で区切った語の条件を外す | 2（名前の規則・拒む削除） |
| 〃 | 語ではなく文字列として `test`・`e2e` を含むかで判定する | 1（名前の規則。`factory_ops_m51_testing` が当たる） |
| 〃 | `factory_ops_` で始まる条件を外す | 1（名前の規則） |
| `temp_databases_spec.rb` の拒む削除 | test の環境の確かめを外す | 1 |
| 〃 | 名前の無い呼び出しの確かめを外す | 最初は 0（名前の規則で拒まれる）。名前を明示するようにと返すことの期待を足した後に 1 |
| `temp_databases_spec.rb` の接続中の削除 | `DROP DATABASE` に `WITH (FORCE)` を付ける | 1 |
| `ci_checks_spec.rb` の `if:` | `publish` の `if:` から `success()` を消す | 1 |
| 〃 | `success()` を `always()` に替える | 1 |
| 〃 | `success() && !cancelled() && …` にする | 1 |
| 〃 | `(success() \|\| failure()) && …` にする | 1 |
| `cross_read_spec.rb` の `pg_locks` の診断の失敗（実装レビューの Codex R2） | `lock_holders` の rescue を外す | 1（この example） |
| `cross_read_spec.rb` の状態の診断の失敗（同上） | `activity` のセーブポイント（`transaction(requires_new: true)`）を外す | 1（この example。呼んだスレッドのトランザクションが壊れる） |
| 〃 | `activity` の rescue を外す | 1（この example。外側の rescue が「引けなかった」とだけ出す） |
| `around_hook_errors_spec.rb` の `skip`（実装レビューの Codex R1） | `skip` を送り返す形に戻す | 1（この example。`got: [2, 2]`） |
| `catalog_spec.rb`（request）の `thenBy` の空の配列 | `Resolvers::SortArguments::Validator` の `return if then_by.blank?` を `then_by.nil?` に替える | 1（この example） |

戻した後に同じ spec を流し、すべて通った。

### 確かめたこと

#### 止まりの前と後（作るもの 4・5）

M50 の壊し方（`Sales::ItemPrices.today_price` の式から `.current` を外す）で `bundle exec rspec packs/sales/spec/public/sales/catalog_spec.rb` を流した。

| 版 | 結果 |
|---|---|
| 直す前（`89fd27e` の補助に `lock_timeout` だけを足した版） | 7 分を過ぎても終わらず、プロセスを止めた。止まった状態は上の「計画との違い」のとおり |
| 補助の直しだけ（`rails_helper.rb` の include を外して） | 0.39 秒で終わり、19 examples, 3 failures。落ちた example（`PG::CardinalityViolation` と around の `PG::InFailedSqlTransaction`）のほかに、後ろの 2 つのグループが「所有ロールの接続にトランザクションが残っている（1 段）」で落ちた |
| 2 つの直しの後（`d25b9f1`） | 2 秒で終わり、19 examples, 1 failure。落ちたのは壊した単価の example だけで、後ろのグループ（RLS の SELECT と UPDATE を開く文脈を含む）は通った |

`lock_timeout` の値は、正常な実行で `add!`・`remove!` にかかった時間から決めた。`factory_ops_m51_test`（41 のテナントの表）で、`add!` と `remove!` を交互に 10 回流すと、`add!` は最大 0.050 秒（ほかは 0.014〜0.020 秒）、`remove!` は最大 0.025 秒だった。上限は 2 秒で、`add!` の最大の 40 倍、`remove!` の最大の 80 倍である。

打ち切ったときのメッセージは次の形になった（`bin/rails runner` で、アプリのロールの別の接続が `users` の `ACCESS SHARE` のロックを持ったまま流した）。

```text
MatrixCrossRead.add! が users のロックを 2s 待って打ち切った。ロックを持つ接続：pid 33722（factory_app、状態 idle in transaction、トランザクションの開始 2026-10-15 01:49:17.810466+00、最後の問い合わせ LOCK TABLE users IN ACCESS SHARE MODE）
MatrixCrossRead.remove! が users のロックを 2s 待って打ち切った。ロックを持つ接続：pid 33723（factory_app、このスレッドの接続）。matrix_cross_read と matrix_cross_update のポリシーが残った。ロックが解けた後に、RAILS_ENV=test TEST_DATABASE=factory_ops_m51_test bin/rails runner 'require "./spec/support/matrix_world"; require "./spec/support/matrix_cross_read"; MatrixCrossRead.remove!' で外す
```

`add!` は 2.06 秒で失敗した。2 つ目のメッセージのコマンドを、ポリシーが 41 の表に 2 つずつ残った状態で手元で流すと、終了コード 0 で終わり、`pg_policies` の 2 つのポリシーは 0 件になった。

#### `thenBy` の空の配列（作るもの 6）

`spec/requests/catalog_spec.rb` の example で、`orderBy` を省いた `supplier.items(thenBy:)` の応答は次のとおりだった（品目は `A-1`・`B-1` の 2 つ）。

| `thenBy` | 応答 |
|---|---|
| 省く | `{"data" => {"supplier" => {"items" => {"nodes" => [{"code" => "A-1"}, {"code" => "B-1"}], "totalCount" => 2}}}}` |
| `[]` | 省いたときと同じ |
| `[{field: "CODE", direction: "ASC"}]` | `{"errors" => [{"message" => "thenBy requires orderBy", …}], "data" => nil}` |

見込みどおりだったので、検証は直さず、`architecture/graphql-schema.md`「ページングと N+1」の文を直した（OI-202）。

#### 一時の DB のタスク（作るもの 3）

`RAILS_ENV=test bin/rails temp_databases:list` は、作者と担当の一時の DB 14 個を、どれも接続 0 で出した（既定の 3 つと `factory_ops_m49` は出なかった）。`RAILS_ENV=development` では「test の環境でだけ動く」で、既定の DB の名前と名前の無い呼び出しは拒む文で、どれも終了コード 1 で止まった。自分で作った `factory_ops_m51task_test` を `RAILS_ENV=test bin/rails "temp_databases:drop[factory_ops_m51task_test]"` で消した。ほかの担当と作者の一時の DB には触れていない。spec は、example ごとに `factory_ops_spec<乱数>_test` を作って消す。

#### `publish` の条件（M51 のブランチへの push）

`publish` は main への push でしか流れないので、ワークフローの `on.push.branches` に `m51-local-checks` を一時に足し、ブランチへの push で確かめた。push は force push を挟まずに続けた。

| push | commit | ほかのジョブ | `publish` |
|---|---|---|---|
| `manifests` に `if: false` を足した（`ci_checks_spec.rb` の `if:` の example の期待も一時に `manifests` を含めた）。ブランチの最初の push | `849798c` | `manifests` が skip。`lint` と `test` が、`BASE_REF`（`github.event.before`）が `0000…` で分岐点を引けずに落ちた | skip |
| 同じ一時の形のまま、文書の commit を載せた | `56bc85f` | `manifests` が skip、ほかはすべて成功 | skip |
| `if: false` を外した | `4405e83` | すべて成功 | 流れて成功（50 秒）。`Log in to GHCR` と `Push images` のステップは skip |

実行の URL：[`849798c`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38669971813)、[`56bc85f`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38670592359)、[`4405e83`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38671087621)。1 回目は、ブランチの最初の push で `github.event.before` が空の commit になり、`needs` の skip のほかに落ちたジョブも混ざったので、`manifests` の skip だけで止まることは 2 回目で確かめた。GHCR には何も置いていない。`a88fc5f` で一時の契機を戻し、`on.push.branches` は `[ main ]` だけになった。`b25971d` からのワークフローと `ci_checks_spec.rb` の差分は無い。

#### E2E（作るもの 1・2）

`a88fc5f` の作業ツリーに、`start-rails.sh` の `E2E_EAGER_LOAD` と `login` の待ちを環境変数で替えられる一時の計測（ボタンを押してから URL が変わるまでの時間を、ワーカーと何回目のログインかと一緒に出す）を入れ、ワーカー 2 のまま全体を流した（`E2E_DATABASE=factory_ops_m51_e2e PLAYWRIGHT_CHANNEL=chrome npm run test:e2e`、Node 22）。load average はコア数 12 の手元で測った。

| 回 | `eager_load` | ログインの待ち | load average（前 → 後、1 分） | 各ワーカーの最初のログイン | 結果 | 全体 |
|---|---|---|---|---|---|---|
| A4 | なし | 5 秒（既定） | 2.24 → 7.56 | 853 ms・855 ms | 72 passed | 59.7 秒 |
| B1 | あり | 5 秒 | 7.11 → 8.64 | 361 ms・350 ms | 72 passed | 56.6 秒 |
| A5 | なし | 5 秒 | 8.64 → 9.65 | 849 ms・844 ms | 72 passed | 56.0 秒 |
| B2 | あり | 5 秒 | 9.65 → 7.64 | 331 ms・339 ms | 72 passed | 55.1 秒 |

どの回も `acceptance.spec.ts` の 26 件は `E2E_SCREENSHOTS` が無いので skip した。読み込みをそろえると、各ワーカーの最初のログインは約 0.85 秒から約 0.35 秒に縮んだ。負荷の低い手元では、どちらの形もログインの待ちで落ちなかった。

並行の負荷のある手元の 2 回は記録にとどめ、採った形の受け入れには使っていない（待ちの値を決めた材料には使った。上の「計画との違い」）。表の A1〜A3 が無いのは、この 2 回と、DB が止まっていて起動できなかった 1 回にあたるからである。ほかの担当の Node のプロセスと Spotlight の索引で、1 分の load average が 25〜126 だった。`eager_load` なし・待ち 5 秒で、1 回目（`849798c`、load 25 → 29）は 13 failed・59 passed（5.7 分）、2 回目（`4405e83`、load 3.4 → 126）は 12 failed・26 skipped・60 passed（7.0 分）で、どちらもログインの URL の期待の時間切れを含んだ（ボタンを押してから時間切れまでの最長は 15.5 秒。押す操作そのものも遅れた）。負荷のある 3 回目は、共有の DB のコンテナが止まっていて起動できなかったので数えていない（`docker compose up -d --wait db` で起こし直した）。

ログインの待ちは 20 秒にした。負荷のある手元でボタンを押してから時間切れまでが 15.5 秒に達した回があり、IB-117 の `npm ci` の直後の 1 回目も、時間切れの前の 2 件のテストに 10 秒と 17 秒かかっていた。この期待はログインが済んだことを確かめるだけなので、延ばしても製品の遅さを隠さない。ほかの期待の待ちは既定の 5 秒のままである。

採った形（`5a3c2af`。一時の計測を外した版）で、全体を続けて 3 回流し、3 回とも 72 passed（26 skipped）、ログインの時間切れは 0 件だった（56.5 秒・54.3 秒・57.8 秒、load average 2.89〜9.23）。ログインの移り先の URL の期待を `/supplier/dashboard-x|buyer/purchase-orders-x$/` に替えて `admin-only.spec.ts` を流すと、5 件すべてが `toHaveURL` の 20000 ms の時間切れで落ちた。`E2E_EAGER_LOAD` を外しても落ちる example は無い（IB-131）。

#### 手元で流したもの

`00dbb24` の作業ツリーで、Ruby 3.4.11・PostgreSQL 18 で流した。

```sh
TEST_DATABASE=factory_ops_m51_test bundle exec rspec spec/platform/temp_databases_spec.rb spec/matrix/cross_read_spec.rb spec/requests/catalog_spec.rb spec/platform/ci_checks_spec.rb spec/platform/around_hook_errors_spec.rb   # 0 failures
TEST_DATABASE=factory_ops_m51_test bin/ci   # すべての工程が通った。rspec は 3113 examples, 0 failures
cd frontend && E2E_DATABASE=factory_ops_m51_e2e PLAYWRIGHT_CHANNEL=chrome npm run test:e2e   # 上の「E2E」の 3 回（`5a3c2af`）
```

分岐の網羅率の警告は、`5a3c2af` の `bin/ci` で 1 件（`lib/temp_databases.rb` の保守用の接続の後片付けの `connection&.close` の nil の分岐）出た。接続に失敗したときにしか通らない分岐で、接続を `begin` の前に作って `ensure` で必ず閉じる形にし、分岐を外した（`00dbb24`）。`00dbb24` の `bin/ci` では 0 件だった。`bin/check-open-items --due M51` と `bin/check-commit-refs` は、この節と台帳と `handoff.md` を載せた版で流して通した。

実装レビューの直しの後も、`1edb62b` の作業ツリーで `TEST_DATABASE=factory_ops_m51_test bin/ci` を流し、すべての工程が通った（rspec は 3116 examples, 0 failures、分岐の網羅率の警告は 0 件）。直しは spec と補助と文書だけで、E2E は流し直していない。

### 残件の処理

引当先が M51 の行は、着手の前と PR の前に台帳を読んだ。OI-202 は `9b36fb1` で閉じた。OI-203（`decided`）は作るもの 7 で反映した。IB-117・IB-123・IB-130 は M51 で実装した。取りまとめ役の判断の受け口（`decisions.md`）で D-1 を読んだ。
