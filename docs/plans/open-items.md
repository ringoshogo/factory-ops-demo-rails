# 残件の台帳

その場で片付けず、決まったマイルストーンまでに決着させる事項（残件）の正本。取りまとめ役は、マイルストーンに着手する前に、引当先がそのマイルストーンの行を読む。マイルストーンを終えるときに、実装者が片付けた行を閉じ、取りまとめ役が片付かなかった行の引当先を書き換える。状態の意味と読み書きの時機は `../guides/dev-cycle.md`「残件の台帳」にある。

新しい残件は、最後の番号の次を振って表の末尾に足す。閉じた行も消さない。表の形と ID の参照は `bin/check-open-items` が CI で確かめる。

| ID | 状態 | 内容 | 出どころ | 引当先 | 結果 |
|---|---|---|---|---|---|
| OI-01 | closed | `Inventory::Adjustment.adjust` が品目の存在を自分で確かめない。いまは mutation の `find_target` が自社の品目に限っているので外から届かない | M11〜M14 の実装レビュー（Low） | M16 | テストで守った。S1 の `Mutation.adjustStock(input.itemId)` の行が、相手の品目 ID で `NOT_FOUND` になることを確かめる。mutation の `find_target` を素通しにすると落ちる（`8a0b84f`） |
| OI-02 | closed | `Inventory::Stock#readonly?` は `update!` を止めるが、クラス単位の `update_all`・`upsert_all` を止めない。いまは使う箇所が無い | M11〜M14 の実装レビュー（Low） | M16 | テストで守った。在庫の行はパッケージの外から参照できないので、在庫のパッケージのコードが一括の書き込みを使わないことを `stock_spec.rb` で確かめる。`update_all` を足すと落ちる（`e068a71`） |
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
| OI-16 | closed | コードと文書の「ID と node」の参照を、見出し「ID と `node`」（`graphql-schema.md`）の表記にそろえ、見出しの文字列で grep して当たるようにする | M15 の実装レビュー（Low の範囲外の残り） | M16 | コードと spec の 5 か所を「ID と `node`」にそろえた（`39ca306`） |
| OI-17 | open | M33 の画面 18 を、一覧の中にコネクションを入れ子にしない規則（M17）に合わせて書き直す | サイクル 01 の計画レビュー（残件の候補） | M33 | |
| OI-18 | open | `data-model.md` の `audit_logs.actor_user_id` に「→」が無く、外部キーかどうかが曖昧。ユーザーは `platform` の外の表なので、コンテキストをまたぐ参照の規則（外部キーを張らない）に合わせて記述をそろえる | サイクル 01 の計画レビュー（残件の候補） | M19 | |
| OI-19 | judgment | `bin/` の検査のスクリプトの spec（`spec/bin`）を、テストの層のガードに入れた。計画の層の表に無い置き場で、構造の規則を確かめる検査と同じく、対象の数に比例して増え、業務の流れを確かめないからである | M16 の実装 | M20 | |
| OI-20 | judgment | S1 の「相手のデータに届かない」結果を、入口の種類ごとに決めた。1 件を引くフィールドは `null`、一覧を ID で絞るフィールドは空、対象を引く mutation は `NOT_FOUND`、`placePurchaseOrder` は相手の有無と取引関係を区別しない `NOT_PERMITTED`（`graphql-schema.md`「ID と `node`」）。計画は「`null` か `NOT_FOUND`」だけを挙げていた | M16 の実装 | M20 | |
| OI-21 | judgment | 既存の request spec を単体へ移さなかった。公開 API の spec と同じ業務の分岐を確かめている example が無かった（分岐を確かめる公開 API の spec が無いものは OI-22）。そのため単体・結合・シナリオの 3 つとも目安を外れ、`bin/test-layers` は警告を出す | M16 の実装 | M20 | |
| OI-22 | open | 公開 API の単体の spec が無い業務の分岐を、単体に書き足し、同じ分岐を確かめる request spec の example を削る。対象は `Purchasing::Ordering.place`（相手の種類ごとの `NOT_PERMITTED`・明細の誤りと上限・伝票番号）、`Sales::PurchaseOrderTranslator`（照合待ち・重複配送・内部 ID を運ばない）、`Sales::PartMappings.register`（全明細の照合で確定・別の取引先の対応を使わない・失効した相手への登録）、`Sales::Catalog` の品目の保存（同じコードの更新・公開の状態を変えない） | M16 の実装（単体 39.8%・結合 46.3% で目安を外れた） | M20 | |
| OI-23 | judgment | 既存の競合テストの 4 ファイルは、同じパッケージの `spec/concurrency` へ移すだけにし、新しく足した補助（`spec/support/concurrency.rb`）へ書き換えなかった。移す変更と書き換える変更を混ぜると、移した後も同じ example が通ることを差分で確かめにくいからである | M16 の実装 | M20 | |
