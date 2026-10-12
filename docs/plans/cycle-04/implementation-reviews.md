# サイクル 4 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M37 RLS が隠す scope の抜けと、読み取りの役割を行列で捕まえる

PR #50（`m37-scope-matrix`、base は `main`）。PR #49（`cycle-04-plan`）が未マージなので、その commit も差分に見える。`b5ed10b` の後の `02eae08`（OI-118・OI-120 の実装の置き場を M32 に移す）は #49 の commit で、`cycle-04-plan` にも push してある。M37 の差分は `02eae08..` である。

Codex は Conditional Go で、High の M37-R1（入れ子のフィールドが親の ID で呼ぶ公開 API が、2 回目の比べ方の外に残る）を直せば Go とした。Claude は Go だった。M37-R1 は直し（OI-128）、M37-R2 と Claude の Low も同じブランチの commit で直した。High があったので、直した版を Codex で読み直した（下の「読み直し」）。どちらの系統も、`b5ed10b..fa1ccf2` の diff を `fa1ccf2` の版で読んだ。Codex はテストを流さず、依頼に書いた実行結果を前提にした。Claude は `fa1ccf2` の worktree を別名のテスト DB で流し、6 つの公開 API の外でも `Billing::Terms` の scope を外して `SupplierView.billingTerms` の 5 件が落ちることを確かめた。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた控えのファイルから結果を読んだ。

| 系統 | 判定 |
|---|---|
| Codex | Conditional Go |
| Claude | Go |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R1） | 指摘（F-1・F-2） |
| 正しさ | 指摘（R2） | 指摘なし |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R1） | 指摘（F-3） |
| 参照の維持 | 指摘（R3） | 指摘（F-2・F-4） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex | R1：GraphQL の入れ子のフィールド（`Import.rowErrors`・`Invoice.items`・`Invoice.taxSummaries` など）が呼ぶ公開 API は、入口の行列が選ばないか、親の ID でしか引かないので、scope を外しても 2 回目が落ちない | 入れ子のフィールドが親の ID で呼ぶ公開 API を `app/graphql` の書き方から集め（28。`Partnerships::Directory.tenants` は取引先の名前を返す仕様なので除く）、全ペルソナの ID を直に渡して、RLS の SELECT を開いても呼んだペルソナの ID にだけ値を返すことを確かめる行を入口の行列に足した。行の無い公開 API があれば列挙の完全性の example が落ちる。足した確かめで `Partnerships::Directory.user_names` が所有の条件を RLS に任せていたことが分かり、操作者のテナントで明示した（OI-128）。計画の作るもの 2 に (7) を足し、`guides/testing.md` に書いた | `11f86fe` |
| Medium | Codex | R2：足すのに失敗した実行も `after(:context)` で外すので、同じテストの DB に先に足した別の実行のポリシーを消す | 足し終えた実行だけが外す。同じ名前のポリシーがあれば、外し方を示して失敗する。1 つのテストの DB で行列を同時に 2 つの実行から流さないことと、途中で止めた実行が残したポリシーの外し方を `guides/testing.md` に書いた | `4170210` |
| Low | Codex | R3：証跡の OI-118 の引当先が「M30 の作るもの 7」のままで、IB-50 に対処が書いてあるように読める | 「M32 の作るもの 10」に直し、時間の上限と対処は IB-50 で決まっていないと書いた | `4ae2ac1` |
| Low | Claude | F-1：`02eae08` が M37 の範囲外の計画・台帳・計画レビューの記録を書き換えている | `02eae08` は #49 の commit（`cycle-04-plan` にも push 済み）で、M37 の差分ではない。節の初めに差分の範囲を書いた | `4ae2ac1` |
| Low | Claude | F-2：証跡の「残件の処理」が M30 のまま | R3 と同じ | `4ae2ac1` |
| Low | Claude | F-3：空振りのガードが、2 回目の行列と同じ要求の経路を通らない | ガードに、scope を外して設定を `on` にしたダッシュボードの要求の応答が変わる example を足した | `4170210` |
| Low | Claude | F-4：`after(:context)` が走る前提の出典が無い | rspec-core 3.13 の `lib/rspec/core/example_group.rb` の所在をコメントに書いた | `4170210` |

違和感は次のように扱った。

- Codex 1・Claude 3：OI-127 の確かめ方は後追いで、並びが決まることの証明ではない → IB-52 に積んだ
- Claude 1：同じテストの DB を複数の実行で使うと、関係の無い失敗に見える → R2 の直しで、同時に流さない規則を `guides/testing.md` に書いた
- Claude 2：途中で止めるとポリシーが残り、治り方がどこにも無い → 同じ名前のポリシーがあれば外し方を示して失敗し、外し方を `guides/testing.md` に書いた
- Claude 4：2 回目の比べ方は入口のフィールドまでしか見ない → R1 の直しで、入れ子のフィールドの公開 API を確かめる形にした
- Claude 5：`tenant_enforcement_spec.rb` の `partner_read` の表の一覧が手書きで、読む経路を足す人への案内が無い → `architecture/data-model.md`「RLS」の付け忘れの段落に、その一覧にも足すと書いた

### 読み直し

Codex に、`fa1ccf2..4ae2ac1` の直しを `4ae2ac1` の版で読み直してもらった。判定は Go で、前の指摘（R1〜R3、F-1〜F-4）はすべて解消、どの観点にも High 以上の新しい指摘は無かった。参考の Low が 1 つあり、同じブランチで直した。読み直しで新しい違和感は出なかった。

| 重さ | 指摘 | 対応 | commit |
|---|---|---|---|
| Low（参考） | 計画の判断の撤退コストが「業務のコードは変えない」のままで、`Partnerships::Directory.user_names` の直しと合わない | 撤退コストに、2 回目が見つけた scope の抜けの直しは撤退しても残すと書いた | この記録と同じ commit |

### 実装の記録

#### 試作と分かれ目

作るもの 1 の試作を、`b5ed10b` の worktree と別名のテスト DB（`factory_ops_demo_rails_test_m37proto`）で流した。補助（`spec/support/matrix_cross_read.rb`）と `MatrixWorld.share_per_file(cross_read: true)` と、入口の行列の読み取りの行で設定を `on` にして送り直す比べ方だけを置いた形である。結果は次のとおりで、判断の裏返る条件には当たらなかったので、既定の推奨（テストの DB にだけポリシーを足し、入口の行列を 2 回目に流す）で進めた。

| 確かめたこと | 結果 |
|---|---|
| ポリシーの足し外しが世界のロックと待ち合わないか | 世界を開く前の足しは 0.03 秒、閉じた後の外しは 0.02 秒で終わった。対照として、世界を開いたまま `lock_timeout` を 1 秒にして 1 つの表のポリシーを外すと、1.0 秒で `ActiveRecord::LockWaitTimeout` になった。足し外しは世界の前後でだけ行う |
| 2 回目の入口の行列で、scope を外した入口が落ちるか | `Sales::SalesOrders.list` の scope を外すと、`SupplierView.salesOrders` の 5 ペルソナが落ちた（328 examples, 5 failures）。外さなければ 328 examples, 0 failures |
| 試作の後にポリシーが残らないか | `pg_policies` の `matrix_cross_read` は 0 行 |

#### RED と、壊して落ちる記録

補助と世界を先に試作したので、ガードの spec は実装の後に書いた。計画が最初に落ちるとした `matrix_world_spec.rb` のガードは、補助の `MatrixCrossRead.add!` を何もしない形にして流し、期待の不一致で落ちることを確かめた（`7db35c2` の上で、`bundle exec rspec spec/matrix/matrix_world_spec.rb -e "世界の間だけポリシーがあり"`、1 example, 1 failure）。設定を `on` にした生 SQL が、40 の表のどれでも `supplier` の行しか読まず、ダッシュボードの 4 つの集計が scope を外しても変わらなかった。読み取りの行の `member` の期待（`viewer.auditLogs` は `FORBIDDEN`、`viewer.partnerCode` は `null`）は仕様の値で初めから書いた。ほかは次の壊して落ちる記録で RED に代える。

壊したファイルは複製から戻し、壊すときと戻すときに更新時刻を進めた。ポリシーが残る壊し方の後は、補助の `remove!` で外し、`pg_policies` が 0 行に戻ったことを確かめた。入口の行列は `bundle exec rspec spec/matrix/graphql_matrix_spec.rb`（463 examples）、ガードは `bundle exec rspec spec/matrix/matrix_world_spec.rb`（10 examples）で、`7db35c2`〜`577c8d8` の上で流した。

scope（6 つの公開 API から 1 つずつ scope を外す。RLS は残す）：

| 壊したもの | 落ちた example |
|---|---|
| `Sales::SalesOrders.list` | 5：`SupplierView.salesOrders` の 5 ペルソナ。どれも「RLS の SELECT を開くと応答が変わった」で、1 回目の期待は落ちない |
| `Inventory::Stocks.list` | 5：`SupplierView.stocks` の 5 ペルソナ。同上 |
| `Sales::SalesOrders.count_by_status` | 5：`SupplierView.dashboard` の 5 ペルソナ。同上 |
| `Inventory::Stocks.below_safety_stock` | 5：`SupplierView.dashboard` の 5 ペルソナ。2 回目の要求が、他社の在庫の品目を自社の品目の公開 API で引けず、`NoMethodError` で落ちる。1 回目の期待は落ちない |
| `Fulfillment::ShipmentRequests.due_within` | 5：`SupplierView.dashboard` の 5 ペルソナ。「RLS の SELECT を開くと応答が変わった」 |
| `Billing::BillableItems.unbilled_total` | 5：同上 |

2 つの守り（RLS を開いて scope を残す）：入口の行列の 1 回目の要求の前にも設定を `on` にし、両方の要求で RLS の SELECT を開いたまま流すと、6 つの公開 API を通る 3 つの行（`SupplierView.salesOrders`・`SupplierView.stocks`・`SupplierView.dashboard`）は 30 examples, 0 failures、入口の行列の全体も 463 examples, 0 failures だった。scope と規則だけで、どの入口も同じ応答を返す。scope を外して RLS を残すと 1 回目は落ちないことは、上の表の失敗がすべて 2 回目の比べ方か 2 回目の要求で出たことで確かめた。

ガードと補助：

| 壊したもの | 落ちた example |
|---|---|
| 生 SQL のガードから `MatrixCrossRead.on!` を外す | ガードの 1 件（内側の 1 つ目が、40 の表で `supplier` の行しか読まない） |
| 集計のガードから `MatrixCrossRead.on!` を外す | ガードの 1 件（内側の 2 つ目が、4 つの集計とも変わらない） |
| 集計のガードで scope を外さない | ガードの 1 件（同上） |
| 世界にダッシュボードの行（安全在庫を割る在庫・期限の近い出荷依頼）を足さない | ガードの 1 件（在庫と出荷依頼の 2 つの集計が変わらない） |
| 世界を閉じた後にポリシーを外さない（`matrix_world_spec.rb` と `tenant_enforcement_spec.rb` を続けて流す） | 5：`tenant_enforcement_spec.rb` のポリシーの集合（40 の表に `matrix_cross_read` が残る）と、後に足そうとする `matrix_world_spec.rb` の 4 件 |
| 外すのを `after(:context)` の `ensure` にせず、世界を閉じたときだけ外す | 2：世界を開く途中の失敗の example と、後に続く 1 件（ポリシーが 40 残る） |
| 足すのを 1 つのトランザクションにしない | 2：足す途中の失敗の example（2 つ残る）と、後に続く 1 件 |
| 接続先の名前を確かめない | 1：名前の example（例外にならない） |
| 設定が `on` のときだけ `Page.of` の並びを逆にする | 入口の行列の 41：一覧の行が「一覧の並びだけが変わった」で落ちる（OI-127） |
| 足すのに失敗しても外す（`@matrix_cross_read` ではなく `cross_read` で外す） | 1：同じ名前のポリシーがあるときの example（あった 40 のポリシーが消える） |
| 入口の要求のガードから `MatrixCrossRead.on!` を外す | ガードの 1 件（内側の 3 つ目で、未請求の合計が変わらない） |

R2 の直しの後に、外すのを `ensure` にしない壊し方を流し直し、世界を開く途中の失敗の example と、同じ名前のポリシーがあるときの example の 2 件が落ちることを確かめた（`4170210` の上で）。

最初の形は、世界を開く `before(:context)` で失敗したときに `rescue` でもポリシーを外していた。`rescue` を外しても何も落ちなかった。rspec は `before(:context)` が失敗しても `after(:context)` を走らせ、そこの `ensure` が外すからである。`rescue` を消し、外す箇所を `ensure` の 1 つにした（`b40c3b5`）。

役割と列挙：

| 壊したもの | 落ちた example |
|---|---|
| `Platform::AuditLogPolicy#index?` から `admin?` を外す | 5：`Viewer.auditLogs` の 5 ペルソナの `member`（`forbidden` の期待に `value`） |
| `Types::ViewerType#partner_code` の `admin?` を外す | 5：`Viewer.partnerCode` の 5 ペルソナの `member`（`null` の期待に `value`） |
| 受注の一覧の規則（`Sales::SalesOrderPolicy#list?`）に `admin?` を足す | 15：同じ規則を通る `SupplierView.salesOrders`・`SupplierView.salesOrder`・`SupplierView.dashboard` の 5 ペルソナの `member`（`forbidden` が返る） |
| Viewer の型のメソッドで書いたフィールドを列挙に入れない | 1：入口の列挙の完全性（`Viewer.partnerCode` の期待値に当たるフィールドが無い） |

入れ子のフィールドの公開 API（R1 の直し、`11f86fe` の上で、`bundle exec rspec spec/matrix/graphql_matrix_spec.rb -e "入れ子のフィールド"`、28 examples）。確かめを書いた時点で、`Partnerships::Directory.user_names` の行が期待の不一致で落ちた（呼んだ `supplier` のほかに 4 ペルソナのユーザーの名前が返る）。これを RED とし、所有の条件を明示して通した。

| 壊したもの | 落ちた example |
|---|---|
| `Partnerships::Directory.user_names` の所有の条件を外す | 1：その行（5 ペルソナの名前が返る） |
| `Imports::Runs.row_errors` の scope を外す | 1：その行 |
| `Billing::BillableItems.for_invoice` の scope を外す | 1：その行 |
| `Billing::Invoices.tax_summaries_for` の scope を外す | 1：その行 |
| `Sales::SalesOrders.lines_for` の scope を外す | 1：その行 |
| 列挙から、親の ID を渡す resolver の呼び出しを外す | 1：列挙の完全性（`for_invoice`・`row_errors` の行に当たる呼び出しが無い） |

### 確かめたこと

`4170210`（spec と実装はこの版のまま、文書と台帳と証跡だけを直した作業ツリー）で、Ruby 3.4.11 で M37 の完了条件と共通の完了条件を流した。

```sh
bundle exec rspec spec/matrix spec/db/tenant_enforcement_spec.rb   # 1315 examples, 0 failures
for seed in 1 2 3; do bundle exec rspec spec/matrix --order rand --seed $seed || exit 1; done   # 3 回とも 1306 examples, 0 failures
bin/check-structure                            # 終了コード 0
bin/ci                                         # 全工程が通る（brakeman は警告 0、rspec は 2476 examples, 0 failures）
BASE_REF=origin/main bin/check-branch-coverage # 一覧は空
bin/check-open-items --due M37                 # 終了コード 0
bundle exec rspec --tag concurrency            # 2 回続けて 59 examples, 0 failures
```

試作と完了条件のあとに、`pg_policies` の `matrix_cross_read` が 0 行であることを確かめた。分岐の網羅率の警告は 0 件で、example を足した件数も 0 件である。M37 の差分で計測の対象のファイルの変更は `Partnerships::Directory.user_names` の条件の 1 行で、分岐を足していない。

行列の spec の時間（手元、`bundle exec rspec <ファイル>` を 2 回ずつ）：

| ファイル | 変える前（`b5ed10b`） | 実装レビューの前（`ecb1041`） | 変えた後（`4170210`） |
|---|---|---|---|
| `spec/matrix/graphql_matrix_spec.rb` | 328 examples、6.28 秒・6.37 秒 | 463 examples、8.79 秒・8.70 秒 | 491 examples、7.80 秒・7.69 秒 |
| `spec/matrix/matrix_world_spec.rb` | 6 examples、3.03 秒・2.84 秒 | 10 examples、4.08 秒・4.12 秒 | 11 examples、4.01 秒・5.02 秒 |
| `spec/matrix/table_matrix_spec.rb`（補助は掛けない） | 804 examples、7.32 秒・7.14 秒 | 804 examples、8.26 秒・7.98 秒 | 804 examples、7.23 秒・7.69 秒 |

入口の行列は、読み取りの行の 2 回目の要求と、足した 163 examples（読み取りの行の `member`、`Viewer.partnerCode` の行、入れ子のフィールドの公開 API の 28 行）で、1.5〜2.5 秒（3〜4 割）伸びた。手元の 1 回ごとの揺れが 1 秒ほどある。行列の時間の上限と、遅くなったときにすることは、IB-50 で決まっていない。

### 残件の処理

引当先が M37 の `open` と `blocked-user` は無かった。実装で決めたことは OI-127 に judgment で積んだ。実装レビューの R1 の直しで決めたことは OI-128 に、違和感の 1 つは IB-52 に積んだ。GraphQL を通らない公開 API の所有の条件は、計画どおり範囲外で、M32 の作るもの 10（OI-118）が扱う。

## M30 メトリクス

PR #51（`m30-metrics`、base は `main`）。PR #49（`cycle-04-plan`）と PR #50（`m37-scope-matrix`）が未マージなので、その commit も差分に見える。M30 の差分は `8fc96cc..` である。

どちらの系統も Go だった。Critical と High は無く、Medium と Low はすべて同じブランチの `215448e` で直した。High が無いので、読み直しには出していない。どちらの系統も、`8fc96cc..bab789f` の diff を `bab789f` の版で読んだ。Codex はテストを流さず、対象の commit のコードを読み込む Ruby の実行で M30-R1・M30-R2 を再現した。Claude は `bab789f` の worktree を別名のテスト DB で流し（228 examples, 0 failures）、F-1 を再現し、F-4 を壊して確かめた。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた控えのファイルから結果を読んだ。

| 系統 | 判定 |
|---|---|
| Codex | Go |
| Claude | Go |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R3） | 指摘（F-5） |
| 正しさ | 指摘（R1・R2） | 指摘（F-1・F-2・F-3） |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R1・R2・R3） | 指摘（F-4） |
| 参照の維持 | 指摘なし | 指摘（F-1・F-2・F-3 の文書） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Claude | F-1：`ForbiddenError` を作るときに出どころを積むと、null が伝わって応答から消えた拒否（graphql 2.6.11 は `graphql_dead` の位置のエラーを `context.errors` に載せない）まで数え、後ろの `FORBIDDEN` に別の出どころが当たる。非 null の要素のリストで 2 件を拒否し、別のフィールドを規則で拒否すると、応答の `FORBIDDEN` は 2 件で、出どころは `object`・`object`・`rule` になる | 出どころを `ForbiddenError` に持たせ、`GraphqlController` が応答に載ったエラー（`result.context.errors`）から集める。`check_declarations!` の引数は元に戻した。再現の形を `base_classes_spec.rb` に足し、`graphql-schema.md`「エラー」を直した | `215448e` |
| Medium | Claude | F-2：solid_queue 1.7.0 の `LifecycleHooks#run_hooks_for` はフックの例外を `Exception` ごと拾って起動を続けるので、`PROMETHEUS_EXPORTER_PORT` の無い `bin/jobs` が exporter の無いまま動く | ワーカーのフックを `Platform::Metrics.start_worker_exporter!` にし、設定の誤りでは worker を fork する前に `Kernel.exit!(1)` で終える。登録したフックを呼ぶ example を足し、`guides/config.md`「メトリクス」に Web とワーカーの止まり方を書いた | `215448e` |
| Medium | Codex | M30-R1：文字列でない `query` では、例外の経路の `operation_type` が文書を解析し直して例外になり、イベントが出ず、元の例外も置き換わる | 結果が無く `query` が文字列でなければ、解析し直さずに `none` にする。`query: 123` の要求でイベントが 1 回出て、元の `ArgumentError` が上がる example を足した | `215448e` |
| Medium | Codex | M30-R2：設定に無いキューは、ジョブが無くなった後の収集で 0 を書かず、最後に数えた値が残る | そのプロセスで一度でも数えたキューも 0 で埋める。設定に無いキューのジョブを消して数え直す example を足した | `215448e` |
| Medium | Codex | M30-R3：`correctItemPrice` の request spec が最大値ちょうどを送っていない | 最大値ちょうどに訂正し、訂正後の行を確かめる形にした | `215448e` |
| Low | Claude | F-3：Puma は `WEB_CONCURRENCY` があれば `workers` が無くてもクラスタのモードで起き、`after_booted` が worker の fork の後に動いて、空にしたディレクトリが worker の値を消す | `WEB_CONCURRENCY` を設定した Web のプロセスでは、ディレクトリを空にせずに起動を止める。`puma.rb` のコメントと `guides/config.md` に前提を書いた | `215448e` |
| Low | Claude | F-4：収集のブロックを Web にも登録しても、spec が落ちない | `METRICS_PROCESS=web` の子のプロセスで、キューのゲージを書かないことを確かめる example を足した | `215448e` |
| Low | Claude | F-5：M30-R3 と同じ | M30-R3 と同じ | `215448e` |

違和感は次のように扱った。

- Claude 1：`graphql.operation_completed` は要求のトランザクションの中で出て、コミットに失敗した要求も `ok` と数える → IB-51 に足した
- Claude 2：exporter のポートの衝突と、キューの収集のブロックの失敗が見えにくい → IB-53 に積んだ
- Claude 3：文字列でない `query` の例外の経路 → M30-R1 と同じで、直した
- Claude 4：計画の M18 の節の `graphql.operation_completed` の項目の一覧が古い → 済んだマイルストーンの節で、いまの項目の正本は `guides/config.md`「イベントごとに書く項目」なので、直さない
- Codex 1：親と子が同時に書いた値の集計を spec で確かめていない → IB-54 に積んだ

### 実装の記録

#### RED と、壊して落ちる記録

計画が最初に落とすとした 3 つは、次のとおりに落ちた。

- `metrics_subscriber_spec.rb` の「`graphql.operation_completed` で `graphql_operation_duration_seconds` が増える」：購読者の `emit` とメトリクスの定義を空にした形で、期待の不一致（`expected ... to have changed by 1, but was changed by 0`）で落ちた（`8fc96cc` の上で、`bundle exec rspec spec/platform/metrics_subscriber_spec.rb`、1 example, 1 failure）。
- `mutation_payload_spec.rb`（OI-119）：規則で拒否した mutation と、成功の mutation の後に拒否される mutation を並べた要求の 2 つが、`data` が null でない（`{"establishPartnership" => nil}`、`{"first" => {...}, "denied" => nil}`）期待の不一致で落ちた（`c4d0ccc` の上で、3 examples, 2 failures）。いまの振る舞いは、書き込みを戻した要求で先に成功した mutation の payload を返すことだったので、実装を SDL に合わせた（OI-130）。
- `item_prices_spec.rb`・`catalog_spec.rb` の最大値 + 1（OI-121）：期待の不一致ではなく、保存の時点の `ActiveModel::RangeError` で落ちた（`a7df5eb` の上で、2 examples, 2 failures）。読み込みの失敗と同じく RED に数えず、下の壊して落ちる記録で代える。

ほかの spec は実装の後に書いたので、次の壊して落ちる記録で RED に代える。壊したファイルは複製から戻し、壊すときと戻すときに更新時刻を進めた。`37c3ef7` の上で、壊したファイルを確かめる spec のファイルだけを流した。

購読者と定義（`spec/platform/metrics_subscriber_spec.rb`、21 examples）：

| 壊したもの | 落ちた example |
|---|---|
| `result` の `success` を `ok` に写さない | 2：`graphql_operation_duration_seconds` が増える・`other` になる |
| 登録の表を見ずに操作名をそのまま使う | 1：`other` になる |
| `FORBIDDEN` の出どころを当てず、いつも `none` にする | 1：トップレベルのエラーの数え方 |
| ミリ秒を秒に直さない | 5：時間を数える 5 つのヒストグラム |
| `enqueued_at` の無いジョブを数えないのをやめる | 1：登録を通らずに実行したジョブ |
| `small` の境目を `<` にする | 1：取り込みの大きさ（10,000 行） |
| `total_rows` の無い取り込みを `small` にしない | 1：取り込みの大きさ（行を数える前の失敗） |
| `graphql_operation_duration_seconds` のバケットから 0.5 を外す | 2：0.5 秒の閾値と、ミリ秒を秒に直す example |
| `import_duration_seconds` のバケットから 300 を外す | 1：300 秒の閾値 |
| `external_requests_total` のラベルに `tenant_id` を足す | 2：ラベルの名前の確かめと、そのメトリクスの example |
| 登録の表の `queries` から 1 つ消す | 1：画面の問い合わせの一覧と一致する |

値の置き場と exporter（`spec/platform/metrics_spec.rb`、9 examples）：

| 壊したもの | 落ちた example |
|---|---|
| 設定のキューを 0 で埋めない | 2：キューごとに数える・子のプロセスの `queue_ready_jobs{queue="events"} 0.0`。最初の形は子のプロセスの 1 件だけが落ち、数える example はジョブの無い設定のキューを既定の 0 のままで見ていたので、前もって値を書く形に直した（`37c3ef7`） |
| ゲージの `aggregation: :most_recent` を外す | 1：子のプロセス（`pid` のラベルが付く） |
| `DirectFileStore` を選ばない | 1：子のプロセス |
| 収集のブロックを、どのプロセスにも登録する | 1：ワーカーのプロセスでだけ登録する |
| `PROMETHEUS_EXPORTER_PORT` の確かめを外す | 1 |
| `METRICS_PROCESS` とプロセスの種類の食い違いを許す | 1 |
| `METRICS_PROCESS` の許す値の確かめを外す | 1。最初の形は種類の違いの例外で通っていたので、許す値の一覧の文言で確かめる形に直した（`37c3ef7`） |
| ディレクトリを空にしない | 1 |
| test の環境で立てないのをやめる | 1 |

イベントを出す側：

| 壊したもの | 落ちた example |
|---|---|
| 操作の終わりのイベントを、結果のあるときだけ出す（例外では出さない） | `graphql_entry_spec.rb` の 1：例外のときのイベント |
| code の無いエラーを `none` にしない | `graphql_entry_spec.rb` の 1 |
| 決まらない文書の `operation_type` を `none` にしない | `graphql_entry_spec.rb` の 1 |
| `unauthorized_object` の出どころを `rule` にする | 2：`graphql_entry_spec.rb` の `object` と `base_classes_spec.rb` の型の規則 |
| `unauthorized_field` の出どころを `rule` にする | `base_classes_spec.rb` の 1：フィールドの規則 |
| `enforce_rule!` の出どころを `object` にする | 2：`graphql_entry_spec.rb` の `rule` と `base_classes_spec.rb` のリゾルバ |
| 宣言の無い拒否の出どころを `rule` にする | `base_classes_spec.rb` の 1 |
| `ForbiddenError` が出どころを積まない | 7：出どころを確かめる 6 件と、`FORBIDDEN` のロールバックの 1 件（購読者が足りない出どころで例外を上げる） |
| `ForbiddenError` が出どころの値を確かめない | `base_classes_spec.rb` の 1 |
| SendGrid の接続の失敗でイベントを出さない | `sendgrid_spec.rb` の 1 |
| SendGrid の 429 を `4xx` にまとめる | `sendgrid_spec.rb` の 1 |
| 確実な通知の受け付けのイベントを出さない | `critical_delivery_job_spec.rb` の 1 |
| ログの購読者の項目から `acceptance_ms` を落とす | `logging_spec.rb` の 1 |

OI-119・OI-121：

| 壊したもの | 落ちた example |
|---|---|
| 単価の検証から最大値の上限を外す | 5：request spec の 2 と、公開 API の単体の 3（どれも保存の時点の例外） |
| 単価の上限を `less_than` にする（1 つ下げる） | 5：最大値ちょうどを受け付ける request spec の 2 と単体の 3 |
| mutation の戻り値の `null false` を外す | 8：`mutation_payload_spec.rb` の 2、`partnerships_spec.rb` の役割の 4、`base_classes_spec.rb` の 2 |

#### 確かめたこと

`37c3ef7` に台帳と計画の直しを足した作業ツリー（`40c9e81` と同じ内容）で、Ruby 3.4.11 で M30 の完了条件と共通の完了条件を流した。

```sh
bundle exec rspec spec/platform/metrics_subscriber_spec.rb spec/platform/logging_spec.rb spec/requests/graphql_entry_spec.rb \
  spec/requests/mutation_payload_spec.rb spec/requests/item_prices_spec.rb spec/requests/catalog_spec.rb \
  packs/notifications/spec packs/imports/spec   # 197 examples, 0 failures
bin/ci                                         # 全工程が通る（brakeman は警告 0、rspec は 2521 examples, 0 failures）。2 分 14 秒
BASE_REF=origin/main bin/check-branch-coverage # 一覧は空
bin/check-open-items --due M30                 # 終了コード 0
bundle exec rspec --tag concurrency            # 2 回続けて 59 examples, 0 failures
```

分岐の網羅率の警告は 0 件で、example を足した件数も 0 件である。

手で確かめたこと（開発の環境、`a7df5eb` の後の作業ツリー）：`PROMETHEUS_EXPORTER_PORT=9394 METRICS_PROCESS=web bin/rails server` に `SupplierDashboard` の問い合わせを 1 回流すと、`curl -s localhost:9394/metrics` に `graphql_operation_duration_seconds_bucket{operation="SupplierDashboard",operation_type="query",outcome="ok",le="0.1"} 1.0` などが出た。同じサーバーの Rails のルートの `/metrics` は 404 だった。`PROMETHEUS_EXPORTER_PORT=9395 METRICS_PROCESS=jobs bin/jobs` を起こし、定期のジョブ（`Notifications::ProcessInboxJob`）が 1 回流れた後、`curl -s localhost:9395/metrics` に、fork した worker のプロセスが書いた `job_duration_seconds_count{job_class="Notifications::ProcessInboxJob",queue="default"} 1.0` と、supervisor が数えた `queue_ready_jobs{queue="events"} 0.0` など 4 つのキューの行が出た。`queue_ready_jobs` の行に `pid` のラベルは無かった。

#### 実装レビューの直しの記録

F-1 は、Claude が `bab789f` で再現した結果（応答の `FORBIDDEN` 2 件に、出どころが `object`・`object`・`rule`）を RED に代える。足した example は、直した後の形で応答の 2 件と出どころの 2 件（`object`・`rule`）が対応することを確かめる。ほかの直しは、`215448e` の上で次のように壊して落ちることを確かめ、戻した。

| 壊したもの | 落ちた example |
|---|---|
| 文字列でない `query` を解析し直さない確かめを外す | `graphql_entry_spec.rb` の 1：文字列でない `query` |
| 一度数えたキューを覚えない | `metrics_spec.rb` の 1：設定に無いキューを 0 に戻す |
| ワーカーのフックがプロセスを終えない | `metrics_spec.rb` の 1：ワーカーのフック |
| `WEB_CONCURRENCY` の確かめを外す | `metrics_spec.rb` の 1：クラスタのモード |
| 収集のブロックを Web にも登録する | `metrics_spec.rb` の 1：`METRICS_PROCESS=web` の子のプロセス |
| `correctItemPrice` が最大値ちょうどを拒む | `item_prices_spec.rb` の 1 |
| 出どころを、応答に載ったすべてのエラーから `ForbiddenError` に限らずに集める | `graphql_entry_spec.rb` の 1：トップレベルのエラーのコードを書く example |

開発の環境で、`PROMETHEUS_EXPORTER_PORT` を設定せずに `METRICS_PROCESS=jobs bin/jobs` と `METRICS_PROCESS=web bin/rails server` を起こすと、どちらも 1 秒ほどで終了コード 1 で終わった。

`215448e` で、共通の完了条件を流し直した。

```sh
bin/ci                                         # 全工程が通る（brakeman は警告 0、rspec は 2526 examples, 0 failures）。2 分 7 秒
BASE_REF=origin/main bin/check-branch-coverage # 一覧は空
bin/check-open-items --due M30                 # 終了コード 0
bundle exec rspec --tag concurrency            # 2 回続けて 59 examples, 0 failures
```

### 残件の処理

引当先が M30 の `open` は OI-119・OI-121 で、どちらも閉じた。OI-124 は judgment のまま、出どころのラベルを実装した。実装で決めたことは OI-129〜OI-133 に judgment で積んだ。実装レビューの違和感は IB-51 に足し、IB-53・IB-54 に積んだ。

## M31 SLO と障害対応の手順書

PR #52（`m31-slo`、base は `main`）。PR #49・#50・#51 が未マージなので、その commit も差分に見える。M31 の差分は `ae0fe20..` である。

Codex は Conditional Go で、High の M31-R1 を名指しした。Claude は Go だった。High と Medium は同じブランチの `c6414a2` で直した。High があったので Codex に読み直しを出し（`aa4c725..c6414a2` を `c6414a2` の版で）、M31-R1 は解消、M31-R2 は未解消（Medium）、High 以上の新しい指摘は無く Go だった。M31-R2 は `0c885e0` で直した。Medium なので、もう一度の読み直しには出していない。

どちらの系統も、`ae0fe20..aa4c725` の diff を `aa4c725` の版で読んだ。Claude は `aa4c725` の worktree を別名のテスト DB で流し（100 examples, 0 failures）、実装を壊して確かめ、警報の式を promtool の追加の系列で確かめた。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた控えのファイルから結果を読んだ。Codex は実行の環境から Docker に接続できず、promtool と DB のテストを流さずに、対象の commit を読んで判定した。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Conditional Go（M31-R1） | Go（M31-R2 は未解消の Medium） |
| Claude | Go | — |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R2） | 指摘なし |
| 正しさ | 指摘（R1・R2・R4） | 指摘（F-1・F-2・F-6） |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R2・R3） | 指摘（F-3・F-4・F-5） |
| 参照の維持 | 指摘（R4） | 指摘なし |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex | M31-R1：RLS の手順書の診断が `relforcerowsecurity` とポリシーの名前だけを比べ、`relrowsecurity`（RLS の有効）を見ない。RLS を無効にした表は強制の属性とポリシーを残すので、差が出ずに「DB の守りは崩れていない」と判断する | 表ごとの `relrowsecurity`・`relforcerowsecurity` と、ポリシーの全項目（対象の操作・ロール・`USING`・`WITH CHECK`）を書き出すスクリプトを手順書に置き、疑いのある環境と、手元で `structure.sql` から作り直したテストの DB の出力を比べる形にした。開発の DB で `import_files` の RLS を無効にすると `table import_files false true` の差が出ることを確かめ、戻した | `c6414a2` |
| Medium | Codex | M31-R2：`ImportStalled` の `min_over_time(...[15m]) > 0` は 15 分の観測を保証せず、履歴の無い系列で最初の評価から鳴る | `c6414a2` で 15 分前の値（`offset 15m`）も求めたが、読み直しで、窓の途中で収集が途切れて別のジョブで実行中に戻ると 2 分で鳴ると指摘された。`0c885e0` で、1 分ごとに「実行中なら 1、実行中でないか系列が無ければ 0」にした値（サブクエリ `[15m:1m]`）の最小値で見る形にした。履歴の無い系列・30 分の途切れ・窓の途中の 12 分の途切れの系列を `alerts_test.yml` に足した | `c6414a2`・`0c885e0` |
| Medium | Claude | F-2：M31-R2 と同じ（ワーカーを起こし直した直後に鳴る） | M31-R2 と同じ | `c6414a2`・`0c885e0` |
| Medium | Claude | F-1：`x unless x offset 10m` は、収集が 1 回抜けて 10 分前の値が欠けると、値の変わらない系列を新しい系列と読み、`page` が鳴る | 2 つの「増えた」警報に `for: 2m` を付け、新しい系列の側を 0 でない値に限った。収集の抜けた系列と 0 で現れた系列をテストに足した | `c6414a2` |
| Medium | Claude | F-3：鳴る example がどれも新しい系列の側で鳴り、`increase` の側を外してもテストが通る | 10 分より前からある系列が増えて鳴り、増えないまま 10 分で止む example を、通知の失敗と `FORBIDDEN` の両方に足した | `c6414a2` |
| Medium | Codex | M31-R3：他社のファイルを残す example は RLS が掛かったままで、所有の条件を外しても落ちない | 後始末が流した候補の文（`FOR UPDATE`）を `sql.active_record` で拾い、所有ロールの接続で流し直して、自社のファイルだけを選ぶことを確かめる `files_purge_owner_spec.rb` を足した（`sales_order_policy_spec.rb` と同じ形）。消す文は候補の ID に限り、所有の条件を候補の文の 1 か所にした | `c6414a2` |
| Low | Claude | F-4：M31-R3 と同じ。加えて、`Tenancy.require_tenant!` を外しても `TenantRecord` の `default_scope` が同じ例外を上げるので落ちない | 所有の条件は M31-R3 と同じ。`require_tenant!` は落ちない守りとして IB-59 に積んだ | `c6414a2` |
| Medium | Codex | M31-R4：取り込みの手順書が、取り込みはテナントごとに別のワーカーで動くと書くが、`imports` のワーカーは全テナントで 1 つである | 全テナントが 1 つのワーカーを共有し、止まったジョブが他社の取り込みも待たせると書き、ワーカーを起こし直してから登録し直す止血にした | `c6414a2` |
| Low | Claude | F-5：立てる値の example が `1` だけで、`true` で止まることと、ログアウトを止めないことを確かめていない | `true` で 503 になる example と、立てたときにログアウトが 204 になる確かめを足した | `c6414a2` |
| Low | Claude | F-6：キューの手順書が「Web かワーカーのコンテナ」と書くが、9395 の exporter はワーカーにしか届かない | exporter を読む手順に、流すコンテナ（9395 はワーカー、9394 は Web）を書いた | `c6414a2` |

違和感は次のように扱った。

- Claude 1：予算の消費の警報が短い窓と組んでいない → IB-55 に積んだ
- Claude 2：`alerts_test.yml` は規則と同じ `le` の文字列で書くので、取り込みとの食い違いを捕まえない → IB-56 に積んだ
- Claude 3：キューの手順書のやり直しが、取り込みの失敗したジョブもやり直し、取り込みの手順書の順と食い違う → キューの手順書のやり直しから `Imports::RunJob` を除き、取り込みの手順書で登録し直すと書いた（`c6414a2`）
- Claude 4：計画の M31 の節が、ファイルの受け口の成功を 200 と書く → 成功の状態コード（GraphQL は 200、ファイルの受け口は 201）に直した（`c6414a2`）
- Claude 5：後始末のジョブは、1 社の例外で残りの社を回らない → IB-57 に積んだ
- Claude 6：`JobsFailed` が、残すと決めた失敗のジョブでも鳴り続ける → IB-58 に積んだ
- Codex：なし

### 実装の記録

#### RED と、壊して落ちる記録

計画が最初に落とすとした 3 つは、`ae0fe20` の上で、後始末のジョブを空の `perform` にした形で、期待の不一致で落ちた（`bundle exec rspec spec/platform/alerts_runbook_spec.rb spec/requests/maintenance_mode_spec.rb packs/imports/spec/jobs/imports/purge_abandoned_files_job_spec.rb`、13 examples, 9 failures）。

- `alerts_runbook_spec.rb`：警報の一覧と手順書の一覧が空（`expected [].empty? to be falsey, got true`）で 3 件
- `maintenance_mode_spec.rb`：`expected the response to have status code :service_unavailable (503) but it was :ok (200)`
- `purge_abandoned_files_job_spec.rb`：24 時間 + 1 秒のファイルが残る（`expected: ["item_code,quantity\n", nil] got: ["item_code,quantity\n", "item_code,quantity\n"]`）と、どのテナントのファイルも残るの 2 件。公開 API の 3 件は `NoMethodError` で落ちたので RED に数えず、下の壊して落ちる記録で代える

`lock_sites_spec.rb` は、表に後始末と開始の 2 行を足す前に、表と集めたロックの食い違いで落ちた。ほかの spec と example は実装の後に書いたので、次の壊して落ちる記録で RED に代える。壊したファイルは複製から戻し、壊すときと戻すときに更新時刻を進めた。`343f5c5` の作業ツリーで、壊したファイルを確かめる spec のファイルだけを流した。

後始末と開始（`purge_abandoned_files_job_spec.rb`・`runs_spec.rb`・`purge_lock_spec.rb`、22 examples）：

| 壊したもの | 落ちた example |
|---|---|
| 24 時間ちょうどを消す側に含める（`...` を `..` にする） | 1：24 時間ちょうどと 24 時間 + 1 秒 |
| 消す文の、取り込みの有無の読み直しを外す | 1：`purge_lock_spec.rb` の「開始が先にロック」 |
| ロックの文と消す文の両方から、取り込みの有無の条件を外す | 2：取り込みを始めたファイルを消さない・「開始が先にロック」 |
| 後始末のロック（`.lock`）を外す | 1：「開始が先にロック」（後始末が待たない） |
| ジョブが最初のテナントだけを回る | 2：24 時間の境目・どのテナントのファイルも消す |
| 開始のロックを外す | 1：`purge_lock_spec.rb` の「後始末が先にロック」（開始が待たない） |
| 開始の中身の確かめ（`raise FilePurged`）を外す | 2：中身を消したファイルの `CONFLICT`（単体と競合） |
| 中身の確かめを、取り込み済みの確かめより先にする | 1：取り込みを終えたファイルの 2 回目 |

落ちなかったもの：ロックの文だけから取り込みの有無の条件を外しても落ちない。消す文の読み直しが同じ条件を持つからで、ロックの文の条件は、取り込み済みのファイルをロックしないための絞り込みである。`Tenancy.require_tenant!` を外しても、`TenantRecord` の `default_scope` が同じ例外を上げるので落ちない（IB-59）。所有の条件を外しても、RLS が同じ行を閉じるので落ちなかった。これは実装レビューの M31-R3 で、所有ロールの接続で流し直す example を足した（下の直しの記録）。

メンテナンスの切り替え（`maintenance_mode_spec.rb`、5 examples）：

| 壊したもの | 落ちた example |
|---|---|
| `GraphqlController` から外す | 2：503 を返す・形とセッションの検査より先に止める |
| `ImportFilesController` から外す | 1：503 を返す |
| `prepend_before_action` を `before_action` にする | 1：形とセッションの検査より先に止める（415 が返る） |
| 値があれば立てる読み方にする | 1：`false` のとき |
| ログインのコントローラにも取り込む | 1：ログインは通る |
| Webhook のコントローラにも取り込む | 1：Webhook は受け取る |

警報と手順書（`alerts_runbook_spec.rb`、4 examples）・CI の検査（`ci_checks_spec.rb`）：

| 壊したもの | 落ちた example |
|---|---|
| 警報から `runbook` を消す | 1：手順書のパスを持つ |
| 警報が無い手順書を指す | 2：手順書のパスを持つ・どの手順書も指される |
| 警報が手順書を指さなくなる（別の手順書を指す） | 1：どの手順書も指される |
| 手順書の節の名前を変える | 1：節の順 |
| 共通の完了条件の一覧から `bin/check-alerts` を外す | `ci_checks_spec.rb` の 1 |

警報の規則（`bin/check-alerts`、`a5888fe` と同じ内容の作業ツリーで `alerts.yml` を壊した）：

| 壊したもの | 落ちたテスト |
|---|---|
| 画面の問い合わせの `le="1.0"` を `le="1"` にする | `ScreenQueryLatencyBudgetBurnFast` の 60m |
| 画面の問い合わせから `operation!="other"` を外す | 同上 |
| 通知の失敗から、新しい系列の側を外す | `ReceivedInvoiceNotificationFailed` の 22m |
| `FORBIDDEN` の出どころに `rule` を含める | `ForbiddenByObjectOrUndeclared` の 5m |
| 取り込みの停滞から `or vector(0)` を外す | `ImportStalled` の 26m（行の系列の無い場合） |
| 取り込みの停滞を、実行中の今の値だけで見る | `ImportStalled` の 20m |
| 発注の登録の失敗の閾値の予算を 0.006・0.004 にする | `PlacePurchaseOrderErrorBudgetBurnFast` の 60m（どちらの向きでも） |
| イベントの滞留から `for: 5m` を外す・`>` を `>=` にする | `EventsQueueBacklog` の 4m・6m |

#### 確かめたこと

`343f5c5` に手順書の直しを足した作業ツリー（`aa4c725` と同じ内容）で、Ruby 3.4.11 で M31 の完了条件と共通の完了条件を流した。

```sh
bin/check-alerts                                   # check rules は 30 rules、test rules は SUCCESS
bundle exec rspec spec/platform/alerts_runbook_spec.rb spec/platform/ci_checks_spec.rb spec/requests/maintenance_mode_spec.rb \
  spec/db/lock_sites_spec.rb packs/imports/spec     # 105 examples, 0 failures
bin/ci                                             # 全工程が通る（brakeman は警告 0、rspec は 2546 examples, 0 failures）。2 分 8 秒
BASE_REF=origin/main bin/check-branch-coverage     # 一覧は空
bin/check-open-items --due M31                     # 終了コード 0
bundle exec rspec --tag concurrency                # 2 回続けて 61 examples, 0 failures
```

分岐の網羅率の警告は 0 件で、example を足した件数も 0 件である。

手で確かめたこと（開発の環境、`a5888fe` の後の作業ツリー）：

- Prometheus 3.15.0 のコンテナに、prometheus-client 4.2.5 が書いたヒストグラムの本文を取り込ませると、`le="1"`・`le="60"` は `le="1.0"`・`le="60.0"` になり、`le="0.5"` はそのままだった。規則とテストの `le` はこの表記で書いた
- `PROMETHEUS_EXPORTER_PORT=9394 METRICS_PROCESS=web bin/rails server` と `PROMETHEUS_EXPORTER_PORT=9395 METRICS_PROCESS=jobs bin/jobs` を起こし、テナントとユーザーを作ってログインし、`SupplierDashboard` を 1 回流し、在庫の CSV を置いて取り込んだ。そのうえで、5 つの手順書の「確かめること」のコマンドを 1 回ずつ流し、どれも動いた。キューの止めと再開、失敗したジョブのやり直し、`imports:reenqueue`（終えた取り込みには登録しない）も流した。外部の呼び出しと通知の失敗のメトリクスは、開発の送信先が外部を呼ばないので行が出なかった
- 2 つのコマンドを、流した結果から直した（`aa4c725`）。止めたキューは `SolidQueue::Queue.all` がジョブのあるキューしか返さないので、`SolidQueue::Pause` の表から読む。取り込みの `staged_rows` は、見出しを 1 行目に数えた最後の行番号である
- `MAINTENANCE_MODE=1` で起こした Web は、GraphQL とファイルの受け口が 503、ログインが 204、`/up` が 200 だった

#### 実装レビューの直しの記録

`c6414a2`・`0c885e0` の上で、次のように壊して落ちることを確かめ、戻した。

| 壊したもの | 落ちたもの |
|---|---|
| 2 つの「増えた」警報から `for: 2m` を外す | 2 つの警報の 20m（収集の抜けた系列で鳴る） |
| 通知の失敗・`FORBIDDEN` から `increase` の側を外す | それぞれの 18m・20m・23m |
| 新しい系列の側から `> 0` を外す | `ReceivedInvoiceNotificationFailed` の 23m（0 で現れた系列で鳴る） |
| `c6414a2` の取り込みの停滞から `offset 15m` の条件を外す | `ImportStalled` の 1m・41m |
| `0c885e0` の取り込みの停滞を、系列の値に直に `min_over_time` を掛ける形に戻す | `ImportStalled` の 1m・16m・41m |
| `0c885e0` の取り込みの停滞から、系列が無いときの 0 を外す | 同上 |
| 後始末の候補の文から所有の条件を外す | `files_purge_owner_spec.rb` の 1 |
| `MAINTENANCE_MODE` を `1` のときだけ立てる | `maintenance_mode_spec.rb` の 1：`true` のとき |
| 立てたときにログアウトを止める | `maintenance_mode_spec.rb` の 1：ログインとログアウトは通る |

M31-R1 の手順書の直しは、開発の DB で `import_files` の RLS を無効にして差が出ることと、戻して差が消えることで確かめた。

`0c885e0` で、共通の完了条件を流し直した。

```sh
bin/ci                                             # 全工程が通る（brakeman は警告 0、rspec は 2548 examples, 0 failures）。2 分 5 秒
BASE_REF=origin/main bin/check-branch-coverage     # 一覧は空
bin/check-open-items --due M31                     # 終了コード 0
bundle exec rspec --tag concurrency                # 2 回続けて 61 examples, 0 failures
bundle exec rspec spec/platform/alerts_runbook_spec.rb spec/platform/ci_checks_spec.rb spec/requests/maintenance_mode_spec.rb \
  spec/db/lock_sites_spec.rb packs/imports/spec     # 107 examples, 0 failures
```

### 残件の処理

引当先が M31 の `open` は OI-116 で、閉じた。OI-122・OI-126 は judgment のまま、判断どおりに実装した。実装で決めたことは OI-134〜OI-137 に judgment で積んだ。実装レビューの違和感と落ちない守りは IB-55〜IB-59 に積んだ。
