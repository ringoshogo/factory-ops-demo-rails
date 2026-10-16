# サイクル 09 の知見の収穫

サイクル 09（M52・M53・M54・M55）の実装で分かったことのうち、正本に無いものを正本へ書いた記録である。手順は `guides/cycle-end.md`「2. 知見の収穫」にある。逸脱検査（`conformance.md`）は、ここで足した正本を含めて成果物と突き合わせる。再発防止（`recurrence.md`）は、ここにある知見を 2 度書かない。

読んだものは、サイクルの diff（`git diff 081a134..c35a702`）、振り返りの想定外（`retrospective.md`）、改善の候補（IB-138〜IB-150）、実装レビューの証跡の「実装の記録」、正本（`architecture/`・`adr/`・`guides/`・`README.md`・`showcase.md`・`deploy/README.md`・`handoff.md`）である。diff の層ごとの読み取りは、取りまとめ役とも実装者とも別の Codex に `c35a702` の版を展開したディレクトリで頼み、結果をファイルと行で確かめてから書いた。マイルストーンの中で正本に書き足した分（`testing.md`「層への配分」のテナントで包む補助と戻り値のガード、`config.md` の E2E の読み込みのガードと `publish` の `if:` の迂回、`graphql-schema.md` の進みと公開 API の戻り値、`data-model.md` の停止の表を消した後の導出と在庫の品目の確かめ、ADR 012、`packs-and-packwerk.md`「層ごとの責務」、`deploy/README.md` の写しを埋める手順、`handoff.md`）は済んでいるので、ここではその漏れを拾った。

漏れの中心は、サイクル 06・07・08 と同じく見せどころ（`showcase.md`）である。M53・M54 の仕組みはテーマ 4 に載っていたが、M52 の 2 つのガードと M55 の 3 つの直しはどのテーマにも無く、テーマ 3 の公開 API の箇条には「AR のレコードではなく値のオブジェクト」という、relation を返す公開 API を区別しない前の形が残っていた。ほかに、正本の不正確な文が 2 つあった。

## 正本に書いた項目

| 層 | 項目 | 分類 | 正本の状態 | 書いた文書と節・内容 | 根拠 |
|---|---|---|---|---|---|
| 公開 API | 公開 API はモデルも relation も返さず、値・ID・件数・`OperationResult`・`Page`・`SqlSubquery` で渡すこと。relation を返すと呼ぶ側が判断を迂回できること。全 spec の流れのガードが落とすこと | 作り方 | 古い。規約（`packs-and-packwerk.md`「層ごとの責務」、`graphql-schema.md`）にはあり、見せどころのテーマ 3 は「AR のレコードではなく値のオブジェクト」のままで、テーマ 8 の規約の表に無かった | `showcase.md`「3. 責務と関心の分離」の公開 API の箇条と状態、「8. 機械で守る規約」の表に 1 行 | `0bef45f`・`dbabbea` |
| 公開 API | 調整と在庫数の設定は、呼ぶ側に任せず在庫自身が自社の品目の写しで品目を確かめ、写しの無い品目を何も書かずに拒むこと | 作り方 | 無い。規則は `data-model.md`「在庫（`inventory`）」と ADR 011 にあり、見せどころは品目の写しを並べ替えと検索のためだけに書いていた | `showcase.md`「3. 責務と関心の分離」の在庫の品目の写しの箇条 | `87f2a84`・`6a1ed61` |
| policy・GraphQL | 層ごとの責務の一覧と、3 つのレビューの観点がそれに照らすこと | 作り方 | 無い。一覧は `packs-and-packwerk.md`「層ごとの責務」にあり、見せどころから参照されていなかった | `showcase.md`「3. 責務と関心の分離」の設計判断に 1 行 | `6a1ed61` |
| テスト・画面 | E2E の読み込みの変数を外しても E2E は通るので、変数の効き目と起動のスクリプトの順を別のガードで確かめること | 作り方 | 無い。`config.md`「環境ごとの設定」にあり、見せどころのテーマ 9 の画面の E2E の箇条に無かった | `showcase.md`「9. テスト戦略」の画面の E2E の箇条・状態 | `a2c8225` |
| CI と設定 | `publish` の `if:` が `success()` を書いていても、否定・論理和・比べ・関数の引数で迂回すると落ちた `needs` でも流れるので、その形を spec が落とすこと | 作り方 | 無い。`config.md` の `publish` の段落にあり、見せどころのテーマ 8・10 は `success()` の明示までだった | `showcase.md`「8. 機械で守る規約」の CI の行、「10. 運用性」の公開の配置の箇条・状態 | `a2c8225`・`7b29e31` |
| 表とイベント | 購買が受注・受注明細の ID を持たないのは、イベントが運ばないからではなく、運んでも保存しないからであること | 作り方 | 不正確。`data-model.md`「購買（`purchasing`）」が「イベントが運ばないので購買には入らない」と書き、同じ文書の「イベントの受け口と冪等キー」は「出荷計上」が受注 ID と受注明細 ID を運ぶと書く（`packs/contracts/app/public/contracts/shipment_posted.rb`） | `data-model.md`「購買（`purchasing`）」の相手側の ID の文 | `e4ffc00` |
| テスト | 戻り値のガードが確かめるのは、公開 API の本体と、公開 API に渡すブロックの戻り値で、スタブの戻り値は確かめないこと | 作り方 | 不正確。`testing.md`「層への配分」が「ブロックやスタブが relation かモデルを返すと落ちる」と書くが、ガードは元のメソッドを呼ばないスタブを確かめず（`spec/support/public_api_returns.rb` の冒頭のコメント）、spec はスタブが relation を返して通る対照を持つ（`spec/platform/public_api_returns_spec.rb`） | `testing.md`「層への配分」の戻り値のガードの文 | `0bef45f` |

正本のほかに、spec のコメント 1 つを直した。`spec/requests/purchase_orders_spec.rb` の進みのタイムラインの example が「出荷の計上は受注側の受け手も受ける」と書いていたが、M54 で受注側の受け手を消したので、配送表の受け手は購買だけである（`packs/contracts/app/public/contracts/subscriptions.rb`）。下の「前の形の数え上げ」で見つけた。

## 書かなかった項目

| 層 | 項目 | 理由 |
|---|---|---|
| 表とマイグレーション | 出荷停止の表と出荷依頼の取消の時刻を消し、取消済と審査中を受注から導出すること。戻すマイグレーションが空の表で戻ること | 正本にある（`data-model.md`「出荷（`fulfillment`）」と「取消と出荷の競合を止める場所」、ADR 012）。マイグレーションの書き方は実装の手段 |
| 公開 API | `permitting_suppliers_sql` を ID の集合と副問い合わせに分けたこと、`SqlSubquery#contains` | 正本にある（`graphql-schema.md` の公開 API の戻り値の段落）。Arel の組み立て方は実装の手段 |
| policy | `viewer.partnerCode` の役割の判断を policy に移したこと | 正本にある（`packs-and-packwerk.md`「層ごとの責務」、`graphql-schema.md`）。見せどころへの漏れは上の表の層ごとの責務の行で拾った |
| GraphQL | 進みのタイムラインの公開の範囲・出来事・日付と時刻・並べ方・請求書と発注の組ごとの 1 件 | 正本にある（`graphql-schema.md`「発注側の視点」）。見せどころのテーマ 4 にもある |
| GraphQL | 安全在庫を在庫の公開 API で並べ、100 件に限ること | 正本にある（`graphql-schema.md`）。上限を型から渡す形は実装の手段 |
| ジョブとイベント | 5 つのイベントの発生の時刻、古いペイロードだけを補うこと、再配送で最初の時刻を変えないこと | 正本にある（`data-model.md`「イベントの受け口と冪等キー」）。見せどころのテーマ 4 にもある |
| ジョブとイベント | 同じテナントの中の同期化、ロックの順、「出荷可能」を残す理由、消したイベントの互換を持たないこと | 正本にある（ADR 012、`context-map.md`「コンテキスト間の関係」）。見せどころのテーマ 4 にもある |
| テスト | `TenantExample.run` への置き換えと、直に包む around のガード | 正本にある（`testing.md`「層への配分」、`showcase.md`「9. テスト戦略」）。`after_teardown`・接続の共有の解除・pending の例外の取り方は実装の手段で、`spec/support/tenant_example.rb` のコメントにある |
| テスト | TracePoint で戻り値を読むこと、Prism で公開の特異メソッドを数えること、ガードの例外を `Exception` から継ぐこと、競合テストで子のスレッドの例外を親へ渡すこと | 実装の手段。理由は `spec/support/public_api_returns.rb`・`spec/support/concurrency.rb` のコメントにある |
| CI と設定 | `if:` の引用の文字列を除いてから比べと括弧を調べる手順 | 実装の手段。見せどころには迂回を止める目的だけを書いた |
| 画面 | 「進み」の見出し、取消の出来事の控えめな色、出来事の名前の関数 | 実装の手段（`frontend/components/purchase-order-timeline.tsx`、`frontend/lib/format.ts`）。API の順を画面で並べ替えない規則は `graphql-schema.md` にある |
| 配置 | 写しの無い品目への調整と CSV が拒まれる間の影響と、写しを埋める手順 | 正本にある（`deploy/README.md`「作者の手順」、ADR 012） |
| 引き継ぎ | `handoff.md`「次にやること」が、サイクル 09 を M52 → M55 の順に実装すると書く | 知見ではなく引き継ぎの更新で、台帳の棚卸しでサイクル 09 の終わりの形に直す（`inventory.md`） |
| 開発の道具 | 担当を止める手順を 1 か所にしたこと | M56 で `dev-cycle.md`「担当を止めるとき」に書いた。収穫で足すものは無い |

## 見た層

| 層 | 見たもの | 書いた項目 |
|---|---|---|
| 表とマイグレーション | 停止の表と取消の時刻を消すマイグレーション、請求対象明細の表の説明、`structure.sql`、`data-model.md` | `data-model.md` の購買の文 |
| 公開 API | `Sales::OrderShipping`・`Billing::BillableItems`・`Purchasing::PurchaseOrders.timeline_for`・`Inventory::Adjustment`・`SqlSubquery`、`packs-and-packwerk.md` | 見せどころのテーマ 3・8 |
| policy | `viewer.partnerCode` の policy、層ごとの責務の一覧 | 見せどころのテーマ 3 の設計判断 |
| GraphQL | `PurchaseOrder.timeline`、安全在庫の並べ方、`graphql-schema.md` | 無し |
| ジョブとイベント | 消した 4 つのイベントと受け手、配送表、5 つのイベントの `occurred_at` | 無し |
| テスト | `tenant_example.rb`・`public_api_returns.rb`・`concurrency.rb` と各ガードの spec、`ci_checks_spec.rb`・`e2e_eager_load_spec.rb`、`testing.md` | `testing.md` の戻り値のガードの文、見せどころのテーマ 9 |
| CI と設定 | `.github/workflows/ci.yml`、`config/environments/test.rb`、`config.md` | 見せどころのテーマ 8・10 |
| 画面 | 発注の詳細の進み、`format.ts` と単体、E2E | 無し |
| 配置 | `deploy/README.md` の写しを埋める手順 | 無し |
| 見せどころ・README・引き継ぎ | `showcase.md` 全体、`README.md` の ADR の一覧、`handoff.md` | 見せどころの 8 か所。`handoff.md` は棚卸しで直す |

## 前の形の数え上げ

振る舞いを変えた後の前の形を、`c35a702` の版で数えた（`docs/plans/` を除く。証跡は書いた時点の記録なので数えない）。件数は当たった行の数である。

| パターン | 件数 | 読み |
|---|---|---|
| `ShippingHeld`・`ShippingHoldReleased`・`ShipmentCancelled`・`BillableItemConfirmed` | 各 2 | 計画の M54 の節（消す対象と完了条件の `git grep`）。正本とコードに 0 件 |
| `FulfillmentEventReceiver` | 3 | 計画の M14 の節（その時点の実装）と M54 の節 |
| `Billing::SalesEventReceiver` | 5 | 計画の M21 の節と M54 の節 |
| `shipping_holds` | 6 | 作ったマイグレーションと消すマイグレーション（その時点の形）、計画の M14・M54 の節 |
| `AroundHookErrors`・`around_hook_errors` | 8 | 計画の M51・M52 の節。コードと正本に 0 件 |
| 単語の全体の `permitting_suppliers` | 4 | 計画の M55 の節（変える前の形・RED・完了条件）。呼び出しは 0 件 |
| M55 が直した 4 つの文（`在庫は品目コードを持たない` ほか） | 4 | 計画の M55 の節（直す対象と完了条件）。正本に 0 件 |
| `AR のレコードではなく値のオブジェクト` | 1 | `showcase.md` のテーマ 3。上の表で直した（直した後は 0 件） |
| `スタブが relation かモデルを返す` | 1 | `testing.md`。上の表で直した（直した後は 0 件） |
| `イベントが運ばないので購買には入らない` | 1 | `data-model.md`。上の表で直した（直した後は 0 件） |
| `出荷の計上は受注側の受け手も受ける` | 1 | `spec/requests/purchase_orders_spec.rb` のコメント。直した（直した後は 0 件） |
| `回答が届いた時刻` | 1 | 計画の M53 の節（変える前の文言）。GraphQL の型の説明に 0 件 |
