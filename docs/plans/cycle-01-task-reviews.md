# サイクル 1 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No Go のどれかである。

## M15 コメントの規約と掃除

PR #22。どちらの系統も Conditional Go で、指摘はすべて同じブランチの commit で直した。

| 系統 | 判定 |
|---|---|
| Codex | Conditional Go |
| Claude | Conditional Go |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | Cop の spec が、コメントの解析の境界を守っていない。`=begin`／`=end` を無視するように Cop を壊しても spec が全件通る | 連続する `#` 行と `=begin`／`=end` の中の語を落とす例、文字列・ヒアドキュメントの中の `#` とマジックコメントを通す例を足した。`=begin`／`=end` を無視するように Cop を壊すと spec が落ちることを確かめてから戻した | `2093fb6` |
| Medium | Claude | 「出荷停止中は導出しない」に理由が無く、`data-model.md` の導出表（出荷停止中の行）と食い違って見える（`shipment_request_status.rb`・`shipment_request_status_type.rb`・`shipment_request_status_spec.rb`） | 出荷停止を記録する表（`shipping_holds`）が無いので導出しない、という今の理由を書いた | `1b12b73` |
| Low | Claude | コメントが参照する節名が、見出しの表記（「在庫（`inventory`）」「出荷（`fulfillment`）」）と違う | 見出しどおりバッククォート付きにし、見出しの文字列で grep して当たることを確かめた | `1b12b73` |
| Low | Claude | PR の本文に、完了条件を計画から変えた点が書かれていない | PR の本文に、git grep を合否から外して `bin/rubocop` と Cop の spec に一本化したことと、経緯の語「直した」を「を直した」に絞ったことを書いた | PR の本文 |

## M16 テストの層と重要シナリオ

PR は未作成。実装レビューの判定と指摘は、レビューを受けた後に書く。

| 系統 | 判定 |
|---|---|
| Codex | |
| Claude | |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|

### 実装の記録

テストから書いた順に、落ちた example と、実装を壊して落ちた example を残す。既存の実装を守るテスト（競合テスト・S1・S3・OI-02）は書いた時点で通るので、RED の代わりに、守る防壁を壊して落ちることを確かめた。壊した実装は複製から戻し、DB の RLS は `ENABLE` と `FORCE` に戻したことを `pg_class` で確かめた。

| 対象 | RED／壊し方 | 落ちた example |
|---|---|---|
| `bin/test-layers` | スクリプトが無い | `spec/bin/test_layers_spec.rb` の 6 件すべて（6 examples, 6 failures） |
| `bin/test-layers` | 層を `file_path` で決める | `層は id のファイルの部分で決め、共有の example を定義したファイル（file_path）を見ない` |
| `bin/test-layers` | `exclude` を見ない | `パッケージの concurrency の置き場はシナリオに数え、単体に数えない` |
| `bin/test-layers` | 未分類でも終了コード 0 | `どの層の置き場にも当たらないファイルがあれば、そのファイルを示して失敗する` |
| `fail_if_no_examples` | 設定の前は `--tag concurrency`・`--tag scenario` が 0 件で終了コード 0 | 設定の後は `--tag scenario`（シナリオを足す前）が終了コード 1 |
| S4・OI-03 | `Fulfillment::Instructions.cancel` の出荷依頼の行ロックを外す | `計上がコミットするまで出荷指示の取消は待ち、コミットの後は CONFLICT になる` |
| S4・OI-03 | `Fulfillment::Shipping.post` の出荷依頼の行ロックを外し、引当の消費の失敗を無視する（行ロックだけでは、出荷指示の行ロックと引当の状態が残るので落ちない） | `同じ出荷依頼の計上が同時に来ると、後の計上は先の計上のコミットを待ち、CONFLICT になる。出荷実績は 1 件だけできる` |
| S4・OI-04 | `Fulfillment::SalesEventReceiver` の `rescue ActiveRecord::RecordNotUnique` を外す | `先の配送がコミットするまで後の配送は一意索引で待ち、後の配送は例外を出さずに何も書かない` |
| S4 | `Inventory::Stock.lock_for` の行ロックを外す | `引当がコミットするまで出庫は待ち、…` と `出庫がコミットするまで引当は待ち、…` の 2 件 |
| S3 | `Sales::PurchaseOrderTranslator` の `exists?` と `rescue ActiveRecord::RecordNotUnique` を外す（`exists?` だけでは一意索引が止めるので落ちない） | `同じイベントを 2 回ずつ流すと、照合待ちの受注が対応表の登録で確定し、受注は 1 件で、発注は「受注済」になる` |
| S3 | 「品番照合待ち」の受け手が `accepted_at` を消すようにする | `新しいイベントから流すと、照合待ちの受注が対応表の登録で確定し、受注は 1 件で、発注は「受注済」になる` |
| S1 | 表から `Mutation.setItemPublished(input.itemId)` の行を消す | `ID を取る入口は、すべて表にある（入口を足したら、相手の ID を入れる行を表に足す）` |
| S1・OI-01 | `Mutations::AdjustStock#find_target` を、品目を引かずに自社の値を返すようにする | `発注側のユーザーが Mutation.adjustStock(input.itemId) に相手の ID を入れても、相手のデータに届かない` |
| OI-02 | `Inventory::Adjustment.adjust` に `Stock.where(...).update_all` を足す | `在庫のパッケージのコードは、move! を通らない一括の書き込みを使わない` |

競合テストは、`--tag concurrency` を 15 回続けて流し、15 回とも 12 examples, 0 failures だった。

### S1 の 2 つの手の壊し方

S1 は、ID を取る入口を 16 個集め、入口ごとに 1 つの example で、相手の ID を種類ごとに入れて確かめる（example は列挙の 1 件と合わせて 17 件）。

| 壊し方 | 落ちた example |
|---|---|
| 1. `Purchasing::Ordering.place` の `Partnerships::Access` の確かめを外す | `発注側のユーザーが Mutation.placePurchaseOrder(input.supplierTenantId) に相手の ID を入れても、相手のデータに届かない` |
| 2. `Sales::SalesOrderPolicy` の scope の自社テナントの条件を外し、所有ロールで `ALTER TABLE sales_orders DISABLE ROW LEVEL SECURITY` を流す | `発注側のユーザーが SupplierView.salesOrder(id) に相手の ID を入れても、相手のデータに届かない`、`発注側のユーザーが Mutation.allocateSalesOrder(input.salesOrderId) に相手の ID を入れても、相手のデータに届かない` |

壊し方 2 は、scope だけを外したときと、RLS だけを外したときには、どちらも 17 examples, 0 failures だった。

### 層ごとの表

全件（896 examples, 0 failures）の出力を `bin/test-layers` に渡した結果。未分類のファイルは無い。3 つの層が目安を外れ、警告を出した（OI-21・OI-22）。

| 層 | example | 割合 | 時間 | 目安 |
|---|---|---|---|---|
| 単体 | 92 | 39.8% | 1.95s | 60% 以上 |
| 結合 | 107 | 46.3% | 4.60s | 30% 以下 |
| シナリオ | 32 | 13.9% | 6.33s | 10% 以下 |
| ガード | 665 | — | 209.34s | 数えない |

### 残件の処理

| ID | 処理 |
|---|---|
| OI-01 | S1 の `adjustStock` の行で守り、閉じた |
| OI-02 | 在庫のパッケージのコードを走査する spec で守り、閉じた |
| OI-03 | 計上どうしと、計上と出荷指示の取消の競合テストを足し、閉じた |
| OI-04 | 「出荷可能」を 2 つの接続から同時に届ける競合テストを足し、閉じた |
| OI-16 | 参照を見出しの表記にそろえ、閉じた |

決めたことは OI-19〜OI-21・OI-23 に `judgment` として、単体の spec が無い分岐は OI-22 に `open` として登録した。
