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

実装レビューを受ける前の記録である。各系統の判定と、指摘ごとの対応は、レビューを受けた後に書く。

| 系統 | 判定 |
|---|---|
| Codex |  |
| Claude |  |

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

引当先が M17 の残件は無かった。決めたことは OI-25〜OI-27 に `judgment` として登録した。
