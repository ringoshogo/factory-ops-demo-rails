# サイクル 4 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M37 RLS が隠す scope の抜けと、読み取りの役割を行列で捕まえる

`m37-scope-matrix`（base は `main`）。PR #49（`cycle-04-plan`）が未マージなので、その commit も差分に見える。実装レビューの判定と指摘は、受け取った後にこの節に書く。

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

最初の形は、世界を開く `before(:context)` で失敗したときに `rescue` でもポリシーを外していた。`rescue` を外しても何も落ちなかった。rspec は `before(:context)` が失敗しても `after(:context)` を走らせ、そこの `ensure` が外すからである。`rescue` を消し、外す箇所を `ensure` の 1 つにした（`b40c3b5`）。

役割と列挙：

| 壊したもの | 落ちた example |
|---|---|
| `Platform::AuditLogPolicy#index?` から `admin?` を外す | 5：`Viewer.auditLogs` の 5 ペルソナの `member`（`forbidden` の期待に `value`） |
| `Types::ViewerType#partner_code` の `admin?` を外す | 5：`Viewer.partnerCode` の 5 ペルソナの `member`（`null` の期待に `value`） |
| 受注の一覧の規則（`Sales::SalesOrderPolicy#list?`）に `admin?` を足す | 15：同じ規則を通る `SupplierView.salesOrders`・`SupplierView.salesOrder`・`SupplierView.dashboard` の 5 ペルソナの `member`（`forbidden` が返る） |
| Viewer の型のメソッドで書いたフィールドを列挙に入れない | 1：入口の列挙の完全性（`Viewer.partnerCode` の期待値に当たるフィールドが無い） |

### 確かめたこと

`ecb1041`（spec と実装はこの版のまま、台帳と証跡と引き継ぎだけを足した作業ツリー）で、Ruby 3.4.11 で M37 の完了条件と共通の完了条件を流した。

```sh
bundle exec rspec spec/matrix spec/db/tenant_enforcement_spec.rb   # 1286 examples, 0 failures
for seed in 1 2 3; do bundle exec rspec spec/matrix --order rand --seed $seed || exit 1; done   # 3 回とも 1277 examples, 0 failures
bin/check-structure                            # 終了コード 0
bin/ci                                         # 全工程が通る（brakeman は警告 0、rspec は 2447 examples, 0 failures）
BASE_REF=origin/main bin/check-branch-coverage # 一覧は空
bin/check-open-items --due M37                 # 終了コード 0
bundle exec rspec --tag concurrency            # 2 回続けて 59 examples, 0 failures
```

試作と完了条件のあとに、`pg_policies` の `matrix_cross_read` が 0 行であることを確かめた。分岐の網羅率の警告は 0 件で、example を足した件数も 0 件である。M37 の差分は spec と文書だけで、計測の対象のファイルを変えていない。

行列の spec の時間（手元、`bundle exec rspec <ファイル>` を 2 回ずつ）：

| ファイル | 変える前（`b5ed10b`） | 変えた後（`ecb1041`） |
|---|---|---|
| `spec/matrix/graphql_matrix_spec.rb` | 328 examples、6.28 秒・6.37 秒 | 463 examples、8.79 秒・8.70 秒 |
| `spec/matrix/matrix_world_spec.rb` | 6 examples、3.03 秒・2.84 秒 | 10 examples、4.08 秒・4.12 秒 |
| `spec/matrix/table_matrix_spec.rb`（補助は掛けない） | 804 examples、7.32 秒・7.14 秒 | 804 examples、8.26 秒・7.98 秒 |

入口の行列は、読み取りの行の 2 回目の要求と、足した 135 examples（読み取りの行の `member` と、`Viewer.partnerCode` の行）で、約 2.4 秒（約 4 割）伸びた。表の行列は、世界に足したダッシュボードの行の分だけ伸びた。遅くなったときにすることは IB-50 にある。

### 残件の処理

引当先が M37 の `open` と `blocked-user` は無かった。実装で決めたことは OI-127 に judgment で積んだ。GraphQL を通らない公開 API の所有の条件は、計画どおり範囲外で、M30 の作るもの 7（OI-118）が扱う。
