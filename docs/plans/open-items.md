# 残件の台帳

その場で片付けず、決まったマイルストーンまでに決着させる事項（残件）の正本。取りまとめ役は、マイルストーンに着手する前に、引当先がそのマイルストーンの行を読む。マイルストーンを終えるときに、実装者が片付けた行を閉じ、取りまとめ役が片付かなかった行の引当先を書き換える。状態の意味と読み書きの時機は `../guides/dev-cycle.md`「残件の台帳」にある。

新しい残件は、最後の番号の次を振って表の末尾に足す。閉じた行も消さない。表の形と ID の参照は `bin/check-open-items` が CI で確かめる。

| ID | 状態 | 内容 | 出どころ | 引当先 | 結果 |
|---|---|---|---|---|---|
| OI-01 | judgment | `Inventory::Adjustment.adjust` が品目の存在を自分で確かめない。いまは mutation の `find_target` が自社の品目に限っているので外から届かない。判断：品目の存在は、公開 API では確かめず、mutation の `find_target` が受注の公開 API で自社の品目に限ることをテストで守ることにした。在庫は受注に依存しない（`adjustment.rb` の冒頭）ので、公開 API で確かめるには依存の向きを変えることになるからである。S1 の `Mutation.adjustStock(input.itemId)` の行が、相手の品目 ID で `NOT_FOUND` になることを確かめ、`find_target` を素通しにすると落ちる（`8a0b84f`） | M11〜M14 の実装レビュー（Low） | M16 |  |
| OI-02 | judgment | `Inventory::Stock#readonly?` は `update!` を止めるが、クラス単位の `update_all`・`upsert_all` を止めない。いまは使う箇所が無い。判断：`update_all` などの一括の書き込みは、モデルでは止めず、在庫のパッケージのコードが呼ばないことをテストで守ることにした。一括の書き込みは関連のクラスのメソッドで、`readonly?` のような 1 か所の上書きでは止まらないが、在庫の行はパッケージの外から参照できないからである。`stock_spec.rb` が Prism の構文木から呼び出しを拾い、`lock_for` の `insert_all` のほかを落とす（`e068a71`、`c6e604e`） | M11〜M14 の実装レビュー（Low） | M16 |  |
| OI-03 | closed | 出荷の計上どうし、計上と出荷指示の取消を、2 つの接続で同時に動かすテストが無い。コードでは出荷依頼の行ロックで直列になる | M11〜M14 の実装レビュー（テストの抜け） | M16 | `packs/fulfillment/spec/concurrency/fulfillment/shipping_lock_spec.rb` に、計上どうしと、計上と出荷指示の取消の両方の順を足した（`fb1f0ec`） |
| OI-04 | closed | 「出荷可能」の受け手の重複配送を、本当に同時に届けるテストが無い（いまは `exists?` をスタブにした 1 接続のテストだけ）。レビューの一時的な 2 接続のテストでは 1 件になった | M11〜M14 の実装レビュー（テストの抜け） | M16 | `packs/fulfillment/spec/concurrency/fulfillment/sales_event_receiver_lock_spec.rb` で、2 つの接続から同時に届け、出荷依頼が 1 件になることを確かめた（`fb1f0ec`） |
| OI-05 | judgment | Codex が使えないときは、Claude の系統だけで判定して先へ進め、証跡に書く | 開発の回し方を決めたとき | M20 | |
| OI-06 | blocked-user | GitHub のリポジトリを public にする時期。いまは private | `handoff.md`「決まっていないこと」 | M32 | |
| OI-07 | blocked-user | M33 の著者判断 1：一覧は全件（上限 500 件）を読み切ってから、流用元の関数で並べ替える | `implementation-plan.md` M33「著者判断」 | M33 | |
| OI-08 | blocked-user | M33 の著者判断 2：流用元に無い状況のバッジは、意味の近い既存の色を使い回し、色のトークンを足さない | 同上 | M33 | |
| OI-09 | blocked-user | M33 の著者判断 3：ログインの画面にシードのアカウントを並べる（一覧は 1 つの JSON にまとめ、シードとフロントエンドの両方が読む） | 同上 | M33 | |
| OI-10 | blocked-user | M33 の著者判断 4：サイドバーは受注側と発注側の両方のグループを常に出し、ログイン直後の画面は取引関係の有無で決める | 同上 | M33 | |
| OI-11 | blocked-user | M33 の著者判断 5：セッションの期限の延長は、server action の応答でだけブラウザに写す | 同上 | M33 | |
| OI-12 | blocked-user | M33 の著者判断 6：`supplier.item(id:)` と `viewer.tenant` を足す | 同上 | M33 | |
| OI-13 | blocked-user | M33 の著者判断 7：入荷の一覧の入口は足さず、発注一覧の「入荷予定」のタブで代える | 同上 | M33 | |
| OI-14 | blocked-user | M33 の著者判断 8：公開の配置と、訪問者ごとのデータの分離は作らない | 同上 | M33 | |
| OI-15 | open | `adr/007`「未確認の事項」（SendGrid の 429 の待ち時間のヘッダ、署名付き Webhook のヘッダと方式、送信の API が冪等キーを受け付けないこと）を、SendGrid の文書で確かめる | `adr/007` | M28 | |
| OI-16 | closed | コードと文書の「ID と node」の参照を、見出し「ID と `node`」（`graphql-schema.md`）の表記にそろえ、見出しの文字列で grep して当たるようにする | M15 の実装レビュー（Low の範囲外の残り） | M16 | コードと spec の 5 ファイル 6 行を「ID と `node`」にそろえた（`39ca306`） |
| OI-17 | open | M33 の画面 18 を、一覧の中にコネクションを入れ子にしない規則（M17）に合わせて書き直す。取引先の一覧（`buyer.suppliers`）で取引先を選び、その 1 社のカタログを `buyer.supplier(supplierTenantId:)` で引けばよい（画面の問い合わせ `BuyerSupplierCatalog`） | サイクル 01 の計画レビュー（残件の候補） | M33 | |
| OI-18 | open | `data-model.md` の `audit_logs.actor_user_id` に「→」が無く、外部キーかどうかが曖昧。ユーザーは `platform` の外の表なので、コンテキストをまたぐ参照の規則（外部キーを張らない）に合わせて記述をそろえる | サイクル 01 の計画レビュー（残件の候補） | M19 | |
| OI-19 | judgment | `bin/` の検査のスクリプトの spec（`spec/bin`）を、テストの層のガードに入れた。計画の層の表に無い置き場で、構造の規則を確かめる検査と同じく、対象の数に比例して増え、業務の流れを確かめないからである | M16 の実装 | M20 | |
| OI-20 | judgment | S1 の「相手のデータに届かない」結果を、入口の種類ごとに決めた。1 件を引くフィールドは `null`、一覧を ID で絞るフィールドは空、対象を引く mutation は `NOT_FOUND`、`placePurchaseOrder` は相手の有無と取引関係を区別しない `NOT_PERMITTED`（`graphql-schema.md`「ID と `node`」）。計画は「`null` か `NOT_FOUND`」だけを挙げていた | M16 の実装 | M20 | |
| OI-21 | judgment | 既存の request spec を単体へ移さなかった。公開 API の spec と同じ業務の分岐を確かめている example が無かった（分岐を確かめる公開 API の spec が無いものは OI-22）。そのため単体・結合・シナリオの 3 つとも目安を外れ、`bin/test-layers` は警告を出す | M16 の実装 | M20 | |
| OI-22 | open | 公開 API の単体の spec が無い業務の分岐を、単体に書き足し、同じ分岐を確かめる request spec の example を削る。対象は `Purchasing::Ordering.place`（相手の種類ごとの `NOT_PERMITTED`・明細の誤りと上限・伝票番号）、`Sales::PurchaseOrderTranslator`（照合待ち・重複配送・内部 ID を運ばない）、`Sales::PartMappings.register`（全明細の照合で確定・別の取引先の対応を使わない・失効した相手への登録）、`Sales::Catalog` の品目の保存（同じコードの更新・公開の状態を変えない） | M16 の実装（単体 39.8%・結合 46.3% で目安を外れた） | M20 | |
| OI-23 | closed | 既存の競合テストの 4 ファイルは、同じパッケージの `spec/concurrency` へ移すだけにし、新しく足した補助（`spec/support/concurrency.rb`）へ書き換えなかった。移す変更と書き換える変更を混ぜると、移した後も同じ example が通ることを差分で確かめにくいからである | M16 の実装 | M20 | 実装レビューの指摘で判断を改め、既存の競合テストの 4 ファイルも補助（`spec/support/concurrency.rb`）に寄せた。移したときの後始末は、失敗したときにトランザクションを開いたまま行を消しにいき、ジョブを残すか全テナントの分を消していた（`c2c3fa2`） |
| OI-24 | judgment | 層の割合の「目安を 3 マイルストーン続けて外れたら、単体の割合の下限を失敗の条件に変える」（`implementation-plan.md` M16「判断」）は、OI-22 を片付けた後から数える。M16 では、単体の spec の無い業務の分岐が結合に残っているので 3 つの層とも外れ、そのまま数えると M18 で条件に当たるからである。OI-22 を片付けても単体 60% に届く見込みは薄いので、目安の値そのもの（単体 60% 以上・結合 30% 以下・シナリオ 10% 以下）の見直しを作者に確かめる | M16 の実装レビュー | M20 | |
| OI-25 | closed | 画面の問い合わせ `BuyerSupplierCatalog` が、取引先の一覧（`buyer.suppliers`）の下でカタログ（`SupplierPartnership.catalog`）を引き、一覧の中にコネクションを入れ子にしない規則に反していた。取引先を 1 つ選んで引く入口がスキーマに無かった | M17 の実装 | M17 | 取引先を 1 社選ぶ `buyer.supplier(supplierTenantId:)` を足し、`BuyerSupplierCatalog` をそれで引く形にした。S1 の表と行列テストに行を足し、一覧の要素の下のコネクションを落とす検査を足した（`b1c5bca`） |
| OI-26 | judgment | `spec/support/bullet.rb` は、factory が動く間だけ Bullet の検出を止める。判断：準備のデータは factory で作り、検証の対象（公開 API）は factory が終わった後に呼ぶ。factory の属性・コールバック・渡したブロックの中で呼んだ公開 API の読み込みは検出されない。Bullet は作ったレコードを N+1 の候補から外し（`_create_record` で 1 件だけ読んだレコードと同じに扱う）、inverse_of で結んだ関連を読み込み済みとみなす。example を `Bullet.profile` で包むだけでは、example の中で factory で作ったレコードを公開 API が読み直しても候補にならず、単体の spec でも予算のテストでも N+1 が見えない。止めない状態では、照合待ちの受注 2 件を対応表の登録で確定する spec が、`Sales::PartMatching.confirm` の受注ごとの明細の読み込みを見逃した | M17 の実装 | M20 |  |
| OI-27 | judgment | クエリ数の予算のテストは、変数の `first` を、一覧の親がコネクションの問い合わせにだけ渡す。判断：`supplier.partnerships` と `buyer.suppliers` はリストで返し（親ごとの件数が小さい集まり）、`first` の引数を持たない。計画はすべての問い合わせに `first` を明示するとしていた | M17 の実装 | M20 |  |
