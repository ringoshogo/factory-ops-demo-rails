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
| Low | Codex | R3：証跡の OI-118 の引当先が「M30 の作るもの 7」のままで、IB-50 に対処が書いてあるように読める | 「M32 の作るもの 10」に直し、時間の上限と対処は IB-50 で決まっていないと書いた | この commit |
| Low | Claude | F-1：`02eae08` が M37 の範囲外の計画・台帳・計画レビューの記録を書き換えている | `02eae08` は #49 の commit（`cycle-04-plan` にも push 済み）で、M37 の差分ではない。節の初めに差分の範囲を書いた | この commit |
| Low | Claude | F-2：証跡の「残件の処理」が M30 のまま | R3 と同じ | この commit |
| Low | Claude | F-3：空振りのガードが、2 回目の行列と同じ要求の経路を通らない | ガードに、scope を外して設定を `on` にしたダッシュボードの要求の応答が変わる example を足した | `4170210` |
| Low | Claude | F-4：`after(:context)` が走る前提の出典が無い | rspec-core 3.13 の `lib/rspec/core/example_group.rb` の所在をコメントに書いた | `4170210` |

違和感は次のように扱った。

- Codex 1・Claude 3：OI-127 の確かめ方は後追いで、並びが決まることの証明ではない → IB-52 に積んだ
- Claude 1：同じテストの DB を複数の実行で使うと、関係の無い失敗に見える → R2 の直しで、同時に流さない規則を `guides/testing.md` に書いた
- Claude 2：途中で止めるとポリシーが残り、治り方がどこにも無い → 同じ名前のポリシーがあれば外し方を示して失敗し、外し方を `guides/testing.md` に書いた
- Claude 4：2 回目の比べ方は入口のフィールドまでしか見ない → R1 の直しで、入れ子のフィールドの公開 API を確かめる形にした
- Claude 5：`tenant_enforcement_spec.rb` の `partner_read` の表の一覧が手書きで、読む経路を足す人への案内が無い → `architecture/data-model.md`「RLS」の付け忘れの段落に、その一覧にも足すと書いた

### 読み直し

Codex に、直した版を読み直してもらう。結果はここに書く。

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
