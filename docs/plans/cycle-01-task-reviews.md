# サイクル 1 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No Go のどれかである。

## M15 コメントの規約と掃除

PR #22。どちらの系統も Conditional Go で、指摘はすべて同じブランチの commit で直した。

| 系統 | 判定 |
|---|---|
| Codex | Conditional Go |
| Claude | Conditional Go |

直した後、Codex が対応の commit を読み直し、X1〜X6・C1〜C8・C10〜C12 を解消と判定した。C9 は、Codex から PR の本文を見られなかったので「一部」としたが、本文に 3 件の名前があることを親が確かめた。新しい指摘は無く、M16 に条件は残っていない。

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | Cop の spec が、コメントの解析の境界を守っていない。`=begin`／`=end` を無視するように Cop を壊しても spec が全件通る | 連続する `#` 行と `=begin`／`=end` の中の語を落とす例、文字列・ヒアドキュメントの中の `#` とマジックコメントを通す例を足した。`=begin`／`=end` を無視するように Cop を壊すと spec が落ちることを確かめてから戻した | `2093fb6` |
| Medium | Claude | 「出荷停止中は導出しない」に理由が無く、`data-model.md` の導出表（出荷停止中の行）と食い違って見える（`shipment_request_status.rb`・`shipment_request_status_type.rb`・`shipment_request_status_spec.rb`） | 出荷停止を記録する表（`shipping_holds`）が無いので導出しない、という今の理由を書いた | `1b12b73` |
| Low | Claude | コメントが参照する節名が、見出しの表記（「在庫（`inventory`）」「出荷（`fulfillment`）」）と違う | 見出しどおりバッククォート付きにし、見出しの文字列で grep して当たることを確かめた | `1b12b73` |
| Low | Claude | PR の本文に、完了条件を計画から変えた点が書かれていない | PR の本文に、git grep を合否から外して `bin/rubocop` と Cop の spec に一本化したことと、経緯の語「直した」を「を直した」に絞ったことを書いた | PR の本文 |

## M16 テストの層と重要シナリオ

PR #25。どちらの系統も Conditional Go で、指摘はすべて同じブランチの commit で直した。C9 は PR の本文で直した。

| 系統 | 判定 |
|---|---|
| Codex | Conditional Go |
| Claude | Conditional Go |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex | X1：競合テストが失敗すると、トランザクションを開いたまま後始末に進む。`join(10)` のタイムアウトも確かめない | 補助の `delete_owned_rows` が、止めたスレッドの Queue をすべて解放し、スレッドの終わりを確かめてから消す。終わらなければ行を消さずに失敗する。既存の 4 ファイルも補助に寄せ、OI-23 を閉じた | `c2c3fa2` |
| Medium | Codex | X2：受注の引当のテストが「出荷可能」のジョブを残し、品番の対応表のテストが全テナントのジョブを消す | ジョブの後始末を、その example が作ったテナントを宛先にした `Contracts::EventJob` に限った | `c2c3fa2` |
| Medium | Codex | X3：ロックの待ちの判定が、検査の対象の接続を見ていない | 2 つのスレッドの接続の pid を控え、`pg_blocking_pids(後行)` に先行の pid が含まれることを確かめる。同じ pid なら失敗する | `c2c3fa2` |
| Medium | Codex | X4：先行のトランザクションのコミットの失敗が握りつぶされる | 準備の通知とトランザクションの結果を分け、`commit` と `finish` がスレッドの例外を送出し直す。正常の経路でも先行・後行の両方の結果を確かめる | `c2c3fa2` |
| Medium | Codex | X5：OI-02 の走査は、文字列の中の `#` で禁止の操作を見落とす | Prism の構文木からメソッドの呼び出しを拾い、許す `insert_all` を `lock_for` の中に限った。文字列の補間を含む呼び出しを拾う example を足した。SQL を直接流す書き込み（C12）は、名前で見分けられないので対象外と spec に書いた | `c6e604e` |
| Low | Codex | X6：showcase のタグの説明と、単体のコマンドが層の定義と合わない | タグを置き場ごとに書き分け、単体のコマンドを `--tag ~concurrency` にした | `6f359bd` |
| Medium | Claude | C1：OI-01・OI-02 は片付いていない | `judgment` に改め、テストで守ることにした理由とそのテストの commit を内容の列に書いた。台帳の検査は `judgment` の結果の列を空に保つので、結果の列には書いていない | `6f359bd` |
| Medium | Claude | C2：OI-21・OI-22 と、割合の裏返る条件が食い違う | 数え始めを OI-22 を片付けた後にする判断と、目安の値の見直しを作者に確かめることを OI-24 に登録し、`testing.md` と計画の判断に書いた | `6f359bd` |
| Low | Claude | C3：「data-model.md「在庫」」が見出しと違う | 6 ファイルを「在庫（`inventory`）」にそろえた | `5766a67` |
| Low | Claude | C4：`%r{/spec/scenarios/}` が `packs/*/spec/scenarios` にも当たる | 置き場の正規表現を先頭（`./spec/`・`./packs/<パッケージ>/spec/`）から照合する形にした | `dc7aba0` |
| Low | Claude | C5：`blocked_on_lock?` が DB 全体の待ちを数える | X3 と同じ | `c2c3fa2` |
| Low | Claude | C6：`finish_concurrent_threads` がタイムアウトを黙って通す | X1 と同じ | `c2c3fa2` |
| Low | Claude | C7：`config.after` と各 spec の `after` が重なる | `config.after` を消し、後始末を `delete_owned_rows` に一本化した | `c2c3fa2` |
| Low | Claude | C8：S1 の列挙の example にも重い準備が走る | 入口ごとの example と準備を `describe` に分けた | `dc7aba0` |
| Low | Claude | C9：PR の本文に、手で壊して落ちた example の名前 3 件が無い | PR の本文に書いた | PR の本文 |
| Low | Claude | C10：`testing.md` の「例」と「example」の混在と、まだ無い Bullet の対象外を事実として書いている | 「example」にそろえ、Bullet の文を消した | `6f359bd` |
| Low | Claude | C11：OI-16 の結果の「5 か所」は 5 ファイル 6 行 | 結果を直した | `6f359bd` |
| Low | Claude | C12：一括の書き込みの検査は `connection.execute` の SQL を見ない | 対象外とし、理由を spec のコメントに書いた | `c6e604e` |

競合テストの補助の防壁は、`spec/concurrency/concurrency_helpers_spec.rb` で確かめ、補助を壊して落ちることを見た。

| 補助の壊し方 | 落ちた example |
|---|---|
| 先行のスレッドが、コミットの失敗を送出し直さない | `ブロックの結果を返した後に先行のトランザクションが失敗すると、commit がその例外を送出する` |
| ロックの待ちを、DB 全体の待ちの数で判定する | `ロックの待ちは、後行の接続が先行の接続を待っているときだけ真になり、無関係な接続の待ちを数えない` |
| 先行と後行の pid が同じかを確かめない | `同じスレッドを先行と後行に渡すと失敗する` |
| 後始末で、止めたスレッドを解放しない | `後始末は、コミットさせていないトランザクションを閉じ、スレッドを終わらせる`（後始末が行を消さずに失敗し、テナントが 2 行残ったので、所有ロールで消した） |

`Inventory::Stock.lock_for` の行ロックを外して競合テストを途中で落としたときも、後始末はトランザクションを閉じてから行を消し、テナント・ジョブ・在庫の行は残らなかった。直した後、`--tag concurrency` を 20 回続けて流し、20 回とも 16 examples, 0 failures だった。

直した後の全件は 901 examples, 0 failures で、層ごとの表は次のとおり。未分類のファイルは無く、3 つの層が目安を外れて警告を出した（OI-24）。

| 層 | example | 割合 | 時間 | 目安 |
|---|---|---|---|---|
| 単体 | 93 | 39.4% | 1.21s | 60% 以上 |
| 結合 | 107 | 45.3% | 4.43s | 30% 以下 |
| シナリオ | 36 | 15.3% | 6.19s | 10% 以下 |
| ガード | 665 | — | 214.10s | 数えない |

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
| OI-01 | S1 の `adjustStock` の行でテストで守ることにし、`judgment` にした |
| OI-02 | 在庫のパッケージのコードの呼び出しを Prism で拾う spec で守ることにし、`judgment` にした |
| OI-03 | 計上どうしと、計上と出荷指示の取消の競合テストを足し、閉じた |
| OI-04 | 「出荷可能」を 2 つの接続から同時に届ける競合テストを足し、閉じた |
| OI-16 | 参照を見出しの表記にそろえ、閉じた |

決めたことは OI-19〜OI-21・OI-24 に `judgment` として、単体の spec が無い分岐は OI-22 に `open` として登録した。OI-23 は実装レビューで判断を改めて閉じた。

## M17 N+1 の検出

PR #26。Codex は No Go、Claude は Conditional Go で、指摘はすべて同じブランチの commit で直した。

| 系統 | 判定 |
|---|---|
| Codex | No Go |
| Claude | Conditional Go |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex | X1：HTTP の要求を流すシナリオで、最初の要求の後の直接の呼び出し（イベントの配送）が Bullet の検出の外になる。`Bullet::Rack` が外の包みの検出を上書きして消す | `bullet: false` を置き場ではなく `type: :request` から付け、イベントを流す補助（`deliver_enqueued_events`・`deliver_oldest_event`）が検出の外なら自分で `Bullet.profile` を始めるようにした。要求の後に流したイベントの受け手の N+1 が落ちる example を足した | `0cbcc9a` |
| Medium | Codex | X2：`BuyerSupplierCatalog` が取引先の一覧の下でコネクションを引き、予算のテストは取引先 1 件に固定して増加を隠している | 取引先を 1 社選ぶ `buyer.supplier(supplierTenantId:)` を足し、`BuyerSupplierCatalog` をそれで引く形にした。S1 の表・行列テスト・request spec に行を足し、取引関係の無い相手・失効・存在しない ID・自社のテナントが `null` になることを確かめた。一覧の要素の下のコネクションを落とす検査を足し、OI-25 を閉じた | `b1c5bca`・`9e715f0` |
| Medium | Codex | X3：`rematch` の一括取得を受注ごとの取得に戻しても、spec が落ちない。関連の読み込みでないので Bullet にも見えない | 登録の間に流れる明細の取得の SQL を数え、受注 3 件で 1 回であることを確かめる example を足した | `7975269` |
| Low | Codex | 補足：OI-26 に検証の対象を factory の後に呼ぶことを書き、factory の後の N+1 が例外になる負例を足す。OI-27 に合わせて計画を直す。一括取得の退行を Bullet で捕まえられないことを記録に書く | OI-26 と `graphql-schema.md` に書き、負例を足した。計画の予算の変数の行を直した。記録は下の「実装の記録」に書いた | `0cbcc9a`・`9e715f0` |
| Medium | Claude | C1：`spec/requests` の外で HTTP を流す spec（シナリオ・行列テスト）が二重に包まれ、最初の要求の後で外の検出が消える | X1 と同じ。`graphql-schema.md` と計画の記述を「HTTP の要求を流す example（`type: :request`）」に直した | `0cbcc9a`・`9e715f0` |
| Low | Claude | C2：`BuyerSupplierCatalog` が規則に反し、規則を守らせる検査も無い | X2 と同じ | `b1c5bca` |
| Low | Claude | C3：`rails_helper` の除外を消しても何も落ちない | `type: :request の example は bullet: false を持ち、包まない` を足した | `0cbcc9a` |
| Low | Claude | C4：`testing.md` から、一覧のテストで親を 2 件以上作る規則への参照が無い | 「層への配分」に 1 文と参照を足した | `9e715f0` |
| Low | Claude | C5：許可リストのエラー文が、項目が多すぎる場合を言わない | 「項目は type・class_name・association・reason の 4 つに限る」にした | `0cbcc9a` |

Codex は直した後の差分を読み直し、上の指摘はすべて解消したとして Conditional Go にした。読み直しで出た指摘も同じブランチで直した。

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | X4：`BulletDetection.wrap` は、factory の間の `Bullet.pause` で `Bullet.start?` が偽になるのを検出の外と取り違え、`Bullet.profile` を始める。その `end_request` が外側の収集の状態を消し、再開した後の N+1 が見えない | 検出の中かどうかを、収集の状態（`Bullet.notification_collector`）の有無で見分けるようにした。止めている間に呼んでも収集の状態が残り、再開した後の N+1 が落ちる example を足した。直す前はこの example が「collector が nil」で落ちた | `d04b779` |
| Low | Codex | 入れ子の検査の負例に、コネクションの `nodes`・`edges.node` の下のコネクションが無い | いまのスキーマにはその形の型が無いので、spec の中で小さなスキーマを作り、`orders.nodes.items` と `orders.edges.node.items` を見つけることを確かめた。コネクションの判定を `Types::BaseConnection` から `GraphQL::Types::Relay::ConnectionBehaviors` を持つ型に広げた（エッジの型と、ふつうの型が持つ `edge_type` には当たらない） | `d04b779` |

指摘を直した後に、直した防壁を壊して落ちることを確かめた。

| 壊し方 | 落ちた example |
|---|---|
| `spec/rails_helper.rb` の `type: :request` からの `bullet: false` を外す | `HTTP の要求を流す example（type: :request）は bullet: false を持ち、包まない` |
| イベントを流す補助の検出（`BulletDetection.wrap`）を外す | `HTTP の要求を流した後でイベントを流すと、受け手の中の N+1 で落ちる` |
| factory の間の停止を外す | `factory で作った親を、factory の後に 1 件ずつ関連を読むと落ちる`、`factory で作ったレコードは、…N+1 の候補から外れない` |
| `Partnerships::Directory.for_buyer_supplier` の受注側テナントの条件を外す | `buyer.supplier 取引関係のある受注側テナントで、その 1 社の関係を返す`、`発注側のユーザーが BuyerView.supplier(supplierTenantId) に相手の ID を入れても、相手のデータに届かない` |
| `BuyerSupplierCatalog` を取引先の一覧の下で引く形に戻す | `画面の問い合わせは、一覧の中にコネクションを入れ子にしない` |
| `rematch` の明細を受注ごとに引く | `照合し直す受注の明細は、受注の数によらず 1 回で引く` |
| `BulletDetection.wrap` を、検出の有無を見ずにそのまま動かす形にする | `HTTP の要求を流した後でイベントを流すと、受け手の中の N+1 で落ちる`、`検出の外で呼ぶと、ブロックの間だけ検出を始める` |

直した後の全件は 958 examples, 0 failures で、層ごとの表は次のとおり。未分類のファイルは無く、3 つの層が目安を外れて警告を出した（OI-24）。

| 層 | example | 割合 | 時間 | 目安 |
|---|---|---|---|---|
| 単体 | 95 | 39.4% | 1.36s | 60% 以上 |
| 結合 | 109 | 45.2% | 4.49s | 30% 以下 |
| シナリオ | 37 | 15.4% | 6.23s | 10% 以下 |
| ガード | 717 | — | 210.01s | 数えない |

### 実装の記録

テストから書いた順に、落ちた example と、実装を壊して落ちた example を残す。壊した実装は複製から戻した。

| 対象 | RED／壊し方 | 落ちた example |
|---|---|---|
| Bullet の設定 | 設定の前（gem だけを入れた状態） | `spec/platform/bullet_spec.rb` の 3 つの経路（`公開 API を直接呼ぶと、例外になる`・`Dataloader のソースの中で読んでも、例外になる`・`/graphql への要求は、Bullet のミドルウェアが例外にする`）。どれも「nothing was raised」（4 examples, 3 failures） |
| Bullet の設定 | `Bullet.raise = false` にする | 上の 3 つの経路と `メタデータの無い example は、example の後に例外で落ちる` |
| 自動の包み | `Bullet.profile` を `start_request` と `end_request` だけの包みにする | `メタデータの無い example は、example の後に例外で落ちる` |
| 自動の包み | `bullet: false` を見ない | `bullet: false の example は包まない`、`:concurrency の example は包まない`、`検出の外で factory を使っても、検出を始めない` |
| 自動の包み | `:concurrency` を見ない | `:concurrency の example は包まない` |
| factory の間の停止（OI-26） | 購読を外す | `factory で作ったレコードは、関連の factory で作ったものも含めて、N+1 の候補から外れない` |
| 許可リスト | `reason` の確かめを外す | `reason の無い行は、読み込みの時点で例外にする` |
| クエリ数の予算 | 書いた時点（既存の N+1、下の 1） | `BuyerPurchaseOrders 一覧の親が 1 件と 20 件で、SQL の件数が同じ`（8 件と 27 件） |
| クエリ数の予算 | `Types::SalesOrderType#customer` を、ソースを通さず公開 API を親ごとに呼ぶ形にする | `SupplierSalesOrders 一覧の親が 1 件と 20 件で、SQL の件数が同じ` |
| クエリ数の予算の負例 | `SupplierSalesOrders` の準備で、20 件の受注が同じ得意先を指すようにする | `SupplierSalesOrders customer のソースが公開 API をキーごとに呼ぶと、1 件と 20 件で SQL の件数が違う（負例）` |
| 品番の対応表の登録 | 書いた時点（既存の N+1、下の 2。factory の間の停止を入れた後） | `照合待ちの受注が 2 件あると、登録で両方の明細を照合して確定し、受注ごとに「受注確定」を出す`（`Sales::PartMatching.confirm` の `order.lines` で `UnoptimizedQueryError`） |

Bullet が見るのは関連の読み込みだけである。公開 API の中で親ごとに `where` で子を引き直すクエリは、Bullet にも、画面の問い合わせを通らない経路ではクエリ数の予算にも見えない。`rematch` の一括取得の退行は、実装レビューの指摘（X3）の後に、SQL を数える spec で守った。

Dataloader を外したときに予算が落ちることは、予算の spec の負例が、入れ子ごとに毎回確かめる。負例は、`Sources::PublicApiSource` の作成を包み、対象の公開 API とメソッドの組のソースだけ、`fetch` をキー 1 つずつの呼び出しに差し替える。

`spec/graphql/query_budget_spec.rb` と `spec/platform/bullet_spec.rb` を 3 回続けて流し、3 回とも 39 examples, 0 failures だった。

### 見つけて直した N+1

| | 場所 | 中身 | 直し方 |
|---|---|---|---|
| 1 | `Fulfillment::ShipmentRequestPolicy#show_to_buyer?` | 経路 3 の出荷ごとの認可が、`view_shipments` の付与を受注側ごとに問い合わせていた。答えは受注側ごとに覚えるので、発注の一覧の相手が 20 社なら 20 回問い合わせる | 付与を与えている受注側の集合を、1 回の実行で 1 回だけ引いて覚える |
| 2 | `Sales::PartMappings.rematch` | 照合待ちの受注ごとに明細をロックして引き、確定する受注では `PartMatching.confirm` が `order.lines` で明細を引き直していた | 全受注の明細を受注 → 明細の順に 1 回でロックして引き、確定には引いた明細を渡す |

既存の一覧のテストは、親を 2 件以上作る規則に合わせた（`Partnerships::Directory.for_buyer` の spec、`Fulfillment::PartnerShipments` の spec）。

### 層ごとの表

全件（941 examples, 0 failures）の出力を `bin/test-layers` に渡した結果。未分類のファイルは無い。3 つの層が目安を外れ、警告を出した（OI-24）。

| 層 | example | 割合 | 時間 | 目安 |
|---|---|---|---|---|
| 単体 | 94 | 39.7% | 1.23s | 60% 以上 |
| 結合 | 107 | 45.1% | 4.54s | 30% 以下 |
| シナリオ | 36 | 15.2% | 5.69s | 10% 以下 |
| ガード | 704 | — | 215.40s | 数えない |

### 残件の処理

引当先が M17 の残件は無かった。決めたことは OI-25〜OI-27 に `judgment` として登録した。OI-25 は実装レビューの指摘（X2）で入口を足して閉じた。

## M18 構造化ログと相関 ID

PR #27。Codex は No Go、Claude は Conditional Go で、指摘はすべて同じブランチの commit で直した。

| 系統 | 判定 |
|---|---|
| Codex | No Go |
| Claude | Conditional Go |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex | X1：`operationName` がハッシュ・配列だと、中の値が要求の開始の行と文脈に残る。未認証の要求でも書く | 操作名と変数のキーは、GraphQL の名前の形の文字列だけを、コントローラと購読者の両方で書く。ほかの型と形は中の値ごと落とす。未認証の要求にハッシュ、認証済みの要求に配列、変数のキーに禁止の値を入れる回帰テストを、ログの衛生の spec と購読者の spec と GraphQL の入口の spec に足した | `27d355e` |
| High | Codex | X2：エラー通知の文脈は渡した項目だけが書き換わり、要求の `request_id`・`user_id` や別のテナントがジョブに混ざる。`:job` も実行の後に残る | `perform_now` が、エラー通知の文脈も丸ごと退避し、いまの項目を空にしてからジョブの項目（`job` を含む）を設定し、例外の経路を含めて `ensure` で丸ごと戻す。ジョブの文脈の spec は、直接の `perform_now` を executor の外で動かし、入れ子のジョブと付帯情報の無いジョブを足し、どちらの文脈も項目を絞らずに比べる。OI-30 と `config.md` を合わせた | `27d355e`・`d541e5e` |
| Medium | Codex | X3：本番で `RAILS_LOG_LEVEL=debug` を選べ、SQL のバインド値などを書く | `Platform::Logging.production_level` が `info` より細かい水準を拒み、`production.rb` がそれを通す。`debug` で本番の環境が起動しないことを、子のプロセスで確かめる。`config.md` に既定と許す値を書いた | `27d355e`・`d541e5e` |
| Low | Codex | X4：TaggedLogging を使わない理由（行が JSON で始まらない）が事実と違う | タグがメッセージに混ざるので、文脈を `context` の項目に入れる、と直した（`logging.rb`・`config.md`） | `27d355e`・`d541e5e` |
| Medium | Claude | C1：`ActionMailer::LogSubscriber` が送信の失敗を例外のメッセージ込みで書く | 購読を外し、構成の spec の一覧と `config.md` の表と OI-28 に足した | `27d355e`・`d541e5e` |
| Medium | Claude | C2：要求の側のエラー通知の文脈を確かめるテストが無い | スキーマの実行の中で例外を上げ、通知の文脈に `request_id`・相関 ID・テナント・ユーザーが入ることを確かめる example を足した | `27d355e` |
| Low | Claude | C3：`/up` の要求の行が本番で毎回出る | 購読者が `Rails::HealthController` の要求の行を書かない | `27d355e` |
| Low | Claude | C4：`config.md` の表に `active_job.enqueued_at` が無い | 足した | `d541e5e` |
| Low | Claude | C5：ADR 005 の「付帯情報のテナントはログの文脈にだけ」 | 「ログとエラー通知の文脈にだけ」に直した | `d541e5e` |
| Low | Claude | C6：証跡の数値が再現しない | 下の「実装の記録」の数を直し、流したコマンドを書いた | この commit |
| Low | Claude | C7：ログの衛生の spec が、セッションの Cookie と失敗するログインを流していない | 失敗するログインを足し、ログインで受け取った Cookie の値を禁止の値に入れた | `27d355e` |
| Low | Claude | C8：直接の `perform_now` で上がった例外は、呼び出し元が拾っても `handled: false` で通知される | OI-29 に書いた | `d541e5e` |

Codex は直した後のブランチ（`04efb16`）を読み直し、判定は No Go のままだった。X1・X4・C1〜C8 は解消し、X2・X3 は一部が残った。残りの 3 点（Y1〜Y3）を同じブランチで直した。

| 重さ | 指摘 | 対応 | commit |
|---|---|---|---|
| Medium | Y1（X3 の残り）：環境変数の検証は、`config.log_level = :debug` の直接の指定で迂回できる | 環境変数を検証せず、`production.rb` の `config.after_initialize` で初期化の後の `Rails.logger` の水準を `Platform::Logging.verify_production_level!` に通し、`info` より細かければ起動を止める。子のプロセスで、`RAILS_LOG_LEVEL=debug` と、`production.rb` の後に `config.log_level = :debug` を指定した場合の両方が起動しないことを確かめる | `5118a37`・`b2fb616` |
| Medium | Y2（X2 の残り）：既存の項目を空の値にして書き換えるので、実行の後に `job: nil` やジョブが足した項目が残る。spec の `compact` が差を隠していた | エラー通知の文脈の置き場を、項目の集合ごと置き換える。`ActiveSupport::ExecutionContext.clear` は `Current` の値と入れ子のスタックも捨てるので使わない（Rails 8.1.4 の `execution_context.rb`）。置き換えた後に引数なしの `set` で変更の通知を出す。spec は `compact` をやめて `to_h` をそのまま比べ、本体でジョブが足した項目が実行の後に残らないことも確かめる | `5118a37`・`b2fb616` |
| Low | Y3：同じスレッドで 2 つのジョブの Fiber を交互に動かすと、エラー通知の文脈が混ざる | 直さない。Rails の既定の分離の単位はスレッドで、Solid Queue はジョブをスレッドで動かすので、いまは起きない。前提を OI-35 に `judgment` で登録し、分離の単位が `:thread` であることを確かめる example を足した | `5118a37`・`b2fb616` |

Y1〜Y3 のテストを先に書き、実装の前に流した。39 examples のうち 15 が落ちた（ジョブの文脈 13 件、本番の水準 2 件）。分離の単位のガードは、いまの設定を守るので通った。直した後に壊して、次のとおり落ちることを確かめた。

| 壊し方 | 落ちた example |
|---|---|
| `production.rb` が初期化の後の水準を確かめない | `本番の環境は、RAILS_LOG_LEVEL=debug でも config.log_level = :debug の直接の指定でも起動しない` |
| 水準の確かめで `debug` を許す | `info より細かい水準のロガーを拒み、info 以上を許す` と、上の 1 件 |
| 以前の形（環境変数だけを検証する）に戻す | 上の起動の 1 件（直接の指定で起動した） |
| エラー通知の文脈を、既存の項目を空の値にして書き換える形に戻す | ジョブの文脈の spec の 13 件すべて |
| テストの環境の分離の単位を `:fiber` にする | `Rails の文脈の分離の単位はスレッドである` |

直した後の全件は 1001 examples, 0 failures だった。

指摘のテストを先に書き、実装の前に流した。62 examples のうち 18 が落ちた（ジョブの文脈 11 件、構成と購読者 5 件、ログの衛生 1 件、GraphQL の入口の操作名 1 件）。要求の側のエラー通知の文脈（C2）は、実装がすでにあったので通った。

直した後に、直した防壁を壊して落ちることを確かめた。壊したファイルは複製から戻した。

| 壊し方 | 落ちた example |
|---|---|
| 購読者が操作名を検証せずに書く | `GraphQL の操作名と変数のキーは、GraphQL の名前の形の文字列だけを書く。…`、ログの衛生の 1 件 |
| コントローラが操作名を検証せずに文脈に入れる | `操作名が GraphQL の名前の形の文字列でなければ、ログの文脈にも操作の終わりにも書かない`、ログの衛生の 1 件 |
| 購読者が変数のキーを検証せずに書く | 購読者の操作名の 1 件、ログの衛生の 1 件 |
| エラー通知の文脈を、渡した項目だけ書き換える | ジョブの文脈の spec の 13 件すべて |
| エラー通知の文脈を、実行の後に戻さない | 同じ 13 件 |
| 本番で許す水準に `debug` を足す | `info より細かい水準を拒み、info 以上を許す`、`本番の環境は、RAILS_LOG_LEVEL=debug を与えると起動しない` |
| `production.rb` が水準を `production_level` に通さない | `本番の環境は、RAILS_LOG_LEVEL=debug を与えると起動しない` |
| `ActionMailer::LogSubscriber` を外さない | `params・ジョブの引数・例外のメッセージを文字列で書くフレームワークの購読を外している` |
| `Platform::RequestContext` と `GraphqlController` がエラー通知の文脈を設定しない | `スキーマの実行の中で上がった例外の通知に、request_id・相関 ID・テナント・ユーザーが入る` |
| 購読者がヘルスチェックの要求を書く | `ヘルスチェックの要求は書かない` |

失敗するログインとセッションの Cookie（C7）は、いまの実装がどの行にも書かないことを守るガードで、壊す実装の箇所が無い。

直した後、次のコマンドを 5 回続けて流し、5 回とも 62 examples, 0 failures だった。

```sh
bundle exec rspec spec/jobs/log_context_spec.rb spec/platform/logging_spec.rb spec/requests/log_hygiene_spec.rb spec/requests/graphql_entry_spec.rb spec/contracts/correlation_spec.rb
```

直した後の全件は 1000 examples, 0 failures で、層ごとの表は次のとおり。未分類のファイルは無く、3 つの層が目安を外れて警告を出した（OI-24）。

| 層 | example | 割合 | 時間 | 目安 |
|---|---|---|---|---|
| 単体 | 95 | 38.3% | 1.27s | 60% 以上 |
| 結合 | 116 | 46.8% | 4.39s | 30% 以下 |
| シナリオ | 37 | 14.9% | 6.73s | 10% 以下 |
| ガード | 752 | — | 214.88s | 数えない |

### 実装の記録

テストを先に書き、実装の前に流した。33 examples のうち 32 が落ちた。通った 1 件（`購読者の例外は、テストの環境では呼び出し元まで上がる`）は、Rails が `consider_all_requests_local` から決める既定値を、変えていないことを守るガードである。実装の後、4 つの spec は 33 examples, 0 failures になった。

| 対象 | RED の落ち方 |
|---|---|
| `spec/platform/logging_spec.rb` | 20 件のうち 19 件。`Platform::RequestContext`・`Platform::JsonLogFormatter`・`Platform::JsonLogSubscriber`・`Platform::Logging` が無い（NameError）、ミドルウェアに `Rails::Rack::Logger` と `ActionDispatch::DebugExceptions` が残る、文字列のログの購読が付いている、`log_arguments` が真 |
| `spec/jobs/log_context_spec.rb` | 10 件すべて。イベントと本体の文脈にジョブの項目と付帯情報が無い、エラー通知にテナント ID が付かない、登録し直したジョブに `app_metadata` が無い |
| `spec/contracts/correlation_spec.rb` | 2 件すべて。行に相関 ID が無い |
| `spec/requests/log_hygiene_spec.rb` | 1 件。購読者が無い |

実装を壊して、落ちることを確かめた。壊したファイルは複製から戻した。

| 壊し方 | 落ちた example |
|---|---|
| `Platform::Logging.configure!` が `Rails::Rack::Logger` を外さない | `文脈のミドルウェアは要求 ID を付けた後にあり、要求の開始と例外を文字列で書くミドルウェアは無い`、`ログイン・mutation・URL の変数・失敗する要求とジョブ・イベントの配送の全行が JSON で、禁止の値を含まない` |
| `ActionDispatch::DebugExceptions` を外さない | 同じ 2 件 |
| `ActionController`・`ActionDispatch`・`ActiveJob` の `LogSubscriber` を外さない | `params・ジョブの引数・例外のメッセージを文字列で書くフレームワークの購読を外している`、ログの衛生の 1 件 |
| `SolidQueue::LogSubscriber` を外さない | 同じ 2 件 |
| 購読者が表で項目を絞らず、ペイロードをすべて書く | `要求の開始は params を書かない` など、購読者の 6 件とログの衛生の 1 件 |
| GraphQL のクエリの本文を、要約せずに書く | `GraphQL の要求の開始は、操作名・クエリの SHA-256 の要約・変数のキーの一覧に置き換える`、ログの衛生の 1 件 |
| ハッシュでないペイロードを例外にしない | `ハッシュでないペイロードは例外にする。…`、`イベントのオブジェクトを Rails.event.notify に渡すと、呼び出し元で例外になる` |
| 表に無いイベントもペイロードを書く | `表に無いイベントは、name・context・timestamp だけを書く` |
| `ApplicationJob.log_arguments = false` を消す | `ジョブの引数をログに書かない` |
| 書式が例外のメッセージを書く | `例外を渡されたら、メッセージを書かずにクラス名だけを書く` |
| `Platform::RequestContext` が相関 ID を設定しない | 相関 ID の spec の 2 件 |
| `GraphqlController` が、スキーマを実行した後に文脈を設定する | `要求の開始の行には request_id と相関 ID が付き、テナントとユーザーと操作名はスキーマの実行の中の行から付く` |
| ジョブの文脈を、`perform_now` ではなく `around_perform` で設定する | ジョブの文脈の spec の 10 件のうち 9 件と、相関 ID の spec の 1 件 |
| `perform_now` が、`super` の前に引数を復元する | 引数の復元に失敗するジョブの 3 件（`discard_on では、…`・`retry_on では、…`・`どちらも無ければ、…`） |
| `perform_now` が、実行の前の文脈に戻さない | ジョブの文脈の spec の 10 件のうち 8 件 |
| `perform_now` が、呼び出し元の文脈を消さずに足す | ジョブの文脈の spec の 10 件のうち 9 件 |
| `perform_now` が、上がる例外をエラー通知に送らない | `失敗では、終了のイベントに文脈が付き、エラー通知の文脈にテナント ID が入る`（2 つの経路）、`どちらも無ければ、例外が呼び出し元へ上がり、…` |
| `serialize` が `app_metadata` を入れない | ジョブの文脈の spec の 10 件のうち 7 件と、相関 ID の spec の 2 件（`発注の要求から購買の受け手までの全ログ行が、…`・`相関 ID の無い文脈で発行したイベントは、…`）。相関 ID の無い文脈の example を足す前に壊したときは 1 件だったので、`27d355e` で壊し直して数えた |
| `Contracts.publish` が文脈の因果 ID を付帯情報に入れない | `発注の要求から購買の受け手までの全ログ行が、…受け手の因果 ID は届いたイベントの ID である` |
| ジョブの因果 ID を、届いたイベントの ID ではなく付帯情報の因果 ID にする | 同じ 1 件 |
| 相関 ID の無い文脈で、イベントの ID を相関 ID にしない | `相関 ID の無い文脈で発行したイベントは、そのイベントから一連の処理が始まり、自分の ID を相関 ID にする` |
| `contracts.event_handled` を出さない | 相関 ID の spec の 1 件と、ログの衛生の 1 件 |
| `BaseMutation` がユーザーエラーのコードを集めない | `成功・ユーザーエラー・トップレベルのエラーを分け、ユーザーエラーのコードを書く` |
| `spec/support/log_context.rb` を読み込まない | `example の中で設定したログとエラー通知の文脈は、次の example へ持ち越されない` |
| 購読者が `log/events.log` のパス（`Pathname`）に `write` する | `Rails.event のイベントを、log/events.log の末尾に 1 行ずつ足す` |

壊して落ちなかったものは、テストを直してから壊し直した。

- ジョブの文脈を `around_perform` で設定しても、失敗と再試行の example は通った。`around_perform` で設定した文脈は戻されずに `active_job.completed` まで残るからである。失敗と再試行でも `active_job.started` の文脈を確かめるようにした。
- `ActionDispatch::DebugExceptions` を外さなくても、ログの衛生の spec は通った。テストの環境は rescue できない例外を、`DebugExceptions` が書く前に送出し直すからである。失敗する要求を rescue できる例外にした（OI-33）。
- `SolidQueue::LogSubscriber` を外さなくても、ログの衛生の spec は通った。ワーカーのスレッドを通らないからである。ワーカーと同じ `thread_error` の通知を出すようにした（OI-28）。

RED の後に足した example（`spec/platform/logging_spec.rb` の後始末と `log/events.log` の 2 件、`spec/contracts/correlation_spec.rb` の相関 ID の無い文脈の 1 件、`spec/requests/graphql_entry_spec.rb` の操作の終わりのイベントの 1 件）は、実装の後に書いたので RED が無い。上の表の壊し方で落ちることを確かめた。

計画の手での確認は、次のとおりだった。

- `bin/rails middleware | grep -A1 'Platform::RequestContext'` は、開発の環境で次の行が `Rails::Rack::Logger` だった。本番の環境（`RAILS_ENV=production`）では `Rails::Rack::SilenceRequest` の後にあり、`Rails::Rack::Logger` と `ActionDispatch::DebugExceptions` は無かった。
- 開発の環境で `bin/dev` と `bin/jobs` を動かし、発注を 1 件登録して `grep <相関 ID> log/events.log` を流した。要求の `action_controller.request_started`・`active_job.enqueued`・`graphql.operation_completed`・`action_controller.request_completed` と、受注側テナントの「発注登録」の配送（`active_job.started`・`contracts.event_handled`・`active_job.completed`）と、発注側テナントの「受注確定」の配送が、同じ相関 ID で並んだ。受け手の行の因果 ID は、それぞれが受け取ったイベントの `event_id` だった。
- 最初の確認では、`log/events.log` に 1 行しか残らなかった。購読者が書き込み先の `Pathname` を IO とみなし、`Pathname#write` が書くたびにファイルを作り直していた。購読者は IO だけを受け取り、`initializers/event_log.rb` が追記で開くようにし、追記を確かめる example を足した。

次のコマンドを 5 回続けて流し、5 回とも 93 examples, 0 failures だった。`spec/jobs` と `spec/contracts` はディレクトリごと流したので、ログの spec のほかの example も含む。

```sh
bundle exec rspec spec/platform/logging_spec.rb spec/jobs spec/contracts spec/requests/log_hygiene_spec.rb spec/requests/graphql_entry_spec.rb
```

### 層ごとの表

全件（991 examples, 0 failures）の出力を `bin/test-layers` に渡した結果。未分類のファイルは無い。3 つの層が目安を外れ、警告を出した（OI-24）。

| 層 | example | 割合 | 時間 | 目安 |
|---|---|---|---|---|
| 単体 | 95 | 38.6% | 1.26s | 60% 以上 |
| 結合 | 114 | 46.3% | 5.04s | 30% 以下 |
| シナリオ | 37 | 15.0% | 6.02s | 10% 以下 |
| ガード | 745 | — | 217.57s | 数えない |

### 残件の処理

引当先が M18 の残件は無かった。決めたことは OI-28〜OI-34 に `judgment` として登録した。
