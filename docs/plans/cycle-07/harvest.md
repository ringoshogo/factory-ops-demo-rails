# サイクル 07 の知見の収穫

サイクル 07（M48・M49・M47・M50・M33 の残り）の実装で分かったことのうち、正本に無いものを正本へ書いた記録である。手順は `guides/cycle-end.md`「2. 知見の収穫」にある。逸脱検査（`conformance.md`）は、ここで足した正本を含めて成果物と突き合わせる。再発防止（`recurrence.md`）は、ここにある知見を 2 度書かない。

読んだものは、サイクルの diff（`git diff 2e10f5b..cd585d3`）、振り返りの想定外（`retrospective.md`）、台帳の `judgment` の行（OI-193〜OI-195・OI-197〜OI-201）と改善の候補（IB-114〜IB-128）、実装レビューの証跡の「実装の記録」、正本（`architecture/`・`adr/`・`guides/`・`README.md`・`showcase.md`・`deploy/README.md`）である。diff の層ごとの読み取りは、取りまとめ役とも実装者とも別の Claude のサブエージェントに `cd585d3` の版で頼み、結果をファイルと行で確かめてから書いた。マイルストーンの中で正本に書き足した分（`data-model.md`「文字列の照合順序」と出荷の表とイベントの表、`graphql-schema.md`「ページングと N+1」、`context-map.md` の合計の段落と「受注 → 出荷」「受注 → 在庫」の行、`config.md`「照合順序の版」「CI の工程」、`bin.md`「CI が使うもの」、`testing.md`「行列テストとの分担」、`adr/009`「見直す条件」、`adr/011` 決定 1・2 と引き受けるコスト、`README.md`「開発環境」、`deploy/README.md`）は済んでいるので、ここではその漏れを拾った。

漏れの中心は、サイクル 06 と同じく見せどころ（`showcase.md`）である。サイクル 07 で変わったのはテーマ 4 の照合順序の 1 語だけで、M47・M48・M49・M50 の仕組みはどのテーマにも載っていなかった。

## 正本に書いた項目

| 層 | 項目 | 分類 | 正本の状態 | 書いた文書と節・内容 | 根拠 |
|---|---|---|---|---|---|
| 表とマイグレーション | 運用者が流す `read_models:rebuild` が、出荷依頼の受注番号の写しも作り直して数を出すこと。写す値を運ぶ前に登録したイベントのジョブを配り終えてから流すこと | 手順 | 不正確。運用者が引く表の行が「いまは在庫の品目の写し」のままで、流す時機にジョブを配り終えることが無かった（振り返りの逆向きの照合） | `guides/bin.md`「bin/rails で流す運用のタスク」の `read_models:rebuild` の行 | `5c1a6d8`・`b565125` |
| GraphQL | 品目の一覧は、今日の単価で並べるときに受注の単価の副問い合わせを、安全在庫で並べるときに在庫の公開 API が返す副問い合わせを結ぶ | 作り方 | 欠け。「読み取りの一覧」の品目の行が `Sales::Catalog` だけで、サイクル 06 の収穫で足した受注・発注・出荷依頼の副問い合わせの行とそろっていなかった | `architecture/graphql-schema.md`「読み取りの一覧」の `supplier.items`・`supplier.item`・`Item` の行 | `5c1a6d8` |
| ジョブとイベント | 出荷依頼の受注番号を写さずに、出荷が受注の副問い合わせを結ぶ案を退けた理由（依存の向きを変える、出荷の公開 API に相手の SQL を結ぶ引数が増える） | 決定 | 欠け。`adr/011` 決定 2 はイベントで運ぶ写しも同じタスクと spec で守るとだけ書き、比べた案と理由は台帳（OI-193）と計画の節にしか無かった | `adr/011`「代替案」に D を足した | `81e614c`・`5c1a6d8` |
| テスト | 一覧のために別のコンテキストへ写す値を新しく足す人は、同期かイベントかによらず、作り直しのタスクに写しを足し、一致の spec に書き直しの数を読む列と、写しを空にするか書き換えた対照を足す | 作り方 | 欠け。規則は「品目のコードか名前を書く公開 API を足す人」だけで、M50 のイベントで運ぶ写しを足す人への規則が無かった | `guides/testing.md`「重要シナリオ」の、`DemoWorld` を合わせる段落 | `5c1a6d8` |
| 見せどころ | 複数の列での並べ替え（`thenBy`、画面と API の列の上限をそろえる spec、`IS NOT DISTINCT FROM` で比べる keyset、行列の変種の行、見出しの Shift の操作） | 作り方 | 無い。テーマ 6 の一覧は `orderBy` だけで、状態は M46 で止まっていた | `showcase.md`「6. GraphQL の安全な形」のどこで守っているか・状態 | `02e4561`・`232eee7` |
| 見せどころ | 名前の列の `ja-x-icu`（流用元の `Intl.Collator("ja")` の規則をサーバーで）と品目コードの `pg_c_utf8`、列の照合順序と版の記録を spec で確かめること | 作り方 | 一部。テーマ 4 のロックの順に `pg_c_utf8` の 1 語があるだけだった | `showcase.md`「6. GraphQL の安全な形」の設計判断とどこで守っているか、「8. 機械で守る規約」の表に 1 行 | `31a476a`・`66ff186` |
| 見せどころ | 品目の今日の単価と安全在庫の副問い合わせでの並べ替え、出荷依頼の受注番号をイベントで運んで写すこと、一致の spec の受注番号の対照 | 作り方 | 無い。テーマ 3 の写しは在庫の品目の写しだけ、テーマ 6 の別のコンテキストの値は取引先の名前と品目の写しだけ、テーマ 9 の一致の spec は品目だけだった | `showcase.md`「3. 責務と関心の分離」「6. GraphQL の安全な形」「9. テスト戦略」 | `5c1a6d8`・`b565125` |
| 見せどころ | イベントに項目を足すとき、足す前のジョブのペイロードを `from_payload` だけが補い、`new` は全項目を求めること | 作り方 | 無い。テーマ 4 は登録・冪等キー・ロックの順だけで、規則は `data-model.md`「イベントの受け口と冪等キー」にあった | `showcase.md`「4. 整合性の設計」のどこで守っているか | `5c1a6d8`・`b565125` |
| 見せどころ | CI の `frontend` のジョブの `npm ls --all`、`images` を PR のたびに流すこと、`publish` の `if:` に状態の関数を書かず、`needs` をほかのすべてのジョブちょうどにし、`continue-on-error` を置かないことを spec で守ること | 作り方 | 古い。テーマ 8 の CI の行とテーマ 10 の確かめは M42 の形のままだった | `showcase.md`「8. 機械で守る規約」の CI の行、「10. 運用性」の公開の配置の箇条・確かめ・状態 | `38864fb`・`f08f6fb` |
| README | ADR 011 の説明が、M50 で同じ ADR に載せた出荷依頼の受注番号の写しに触れない | 作り方 | 古い（下読みの違和感） | `README.md` のドキュメントの表の ADR 011 の行 | `5c1a6d8` |

## 書かなかった項目

| 層 | 項目 | 理由 |
|---|---|---|
| 表とマイグレーション | 5 つの列の照合順序、DB の既定の `en_US.utf8`、`LIKE`・`ILIKE` の振る舞い、同じ順位の名前の前後 | 正本にある（`data-model.md`「文字列の照合順序」、`graphql-schema.md`「ページングと N+1」） |
| 表とマイグレーション | 照合順序を変えるマイグレーションを strong_migrations が止めないこと | 実装の手段。マイグレーションのコメントにある。止める手段は改善の候補 IB-118 にある |
| 表とマイグレーション | `template1` の版の記録を改めてから DB を作り直す手順 | 正本にある（`config.md`「照合順序の版」、`deploy/README.md`）。作者の確かめは OI-197 |
| 表とマイグレーション | 単位と受注番号の写しの列を DB の既定の照合順序のままにすること | 確信を持てない。作者の確かめを待つ（OI-199、`author-decisions.md`）。決着で `data-model.md`「文字列の照合順序」の書き方を決める |
| 公開 API | `Page::Sort.of` の配列の引数とカーソルの形、単価のカーソルを `:decimal` にする理由、`put_order_numbers` が値の同じ写しを書き直さないこと | 正本にある（`graphql-schema.md`「ページングと N+1」）か、実装の手段で `page.rb`・`catalog.rb`・`item_prices.rb`・`shipment_requests.rb` のコメントにある |
| 公開 API | 品目の写しと受注番号の写しを同じトランザクションで作り直すこと | 改善の候補 IB-124 にある |
| policy | 変更なし | diff に policy と policy の spec の変更が無い |
| GraphQL | `<型>OrderField` の足した値、`thenBy` の SDL、引数の検証、列の上限、`orderBy` をリストに変えずに `thenBy` を足した理由 | 正本にある（`graphql-schema.md` の表・SDL・「ページングと N+1」。`schema.graphql` と照らした） |
| ジョブとイベント | 「出荷可能」の受注番号、受け手が書き直さないこと、配り終えてから作り直すこと | 正本にある（`data-model.md` のイベントの表と段落、`context-map.md`「受注 → 出荷」、`adr/011` 引き受けるコスト、`README.md`、`deploy/README.md`）。`bin.md` の行だけが欠け、上の表で直した |
| テスト | `collations_spec.rb`・`sort_arguments_spec.rb`・`ci_checks_spec.rb` の example、行列の `thenBy` の変種の行、`logging_spec.rb` が自分のプロセスのログを読むこと | 正本にある（`data-model.md`・`graphql-schema.md`・`config.md`・`testing.md`）。見せどころへの索引だけを上の表で足した |
| テスト | E2E の Shift の確かめを `mousedown` の `defaultPrevented` で行うこと、E2E の世界に足した取消済の 1 組、壊して落ちる記録で rspec が止まること、ログインの待ちの 5 秒 | 実装の手段（E2E と `lib/demo_world.rb` のコメント）か、改善の候補 IB-121・IB-123・IB-117 と OI-201 にある |
| CI と設定 | `image_inputs` を外した理由、暗黙の `success()`、`continue-on-error` を書かないこと、spec が照らす例外 | 正本にある（`config.md`「CI の工程」、`bin.md`「CI が使うもの」、`adr/009`「見直す条件」）。暗黙の `success()` に頼る形は作者に確かめる（`author-decisions.md`） |
| CI と設定 | M48 で測った、キャッシュが空の `images` の時間 | 観測値。規範（予算の内に収まる）は変わらず、`config.md` の引用は 1 つで足りる |
| CI と設定 | 並べて流す rspec の DB の名前に `_test` を含めること | 正本にある（`config.md`「database.yml：同じ DB に 2 つのロールで接続する」と `handoff.md`「開発環境」）。一時の DB の名前の規則と後片付けは改善の探索で扱った（`improvement.md`） |
| 画面 | URL の `sort=a,b&dir=asc,desc` の形、`nextSort` の進め方、番号の幅、`aria-sort` を 1 つ目の列に限ること、1024〜1279px で 2 列を隠すこと | 実装の手段（`frontend/lib/list.ts`・`sortable-head.tsx`・`ui/table.tsx`・`columns.tsx` のコメント）。判断は OI-195・OI-198・OI-200 |
| 画面 | 取消依頼のボタンを出荷の前の発注だけに出すこと、照合待ち・確定待ちのまま取り消した伝票の合計に「取消」 | 正本にある（`context-map.md`「取消の流れ」「発注の連結と品番の照合」、`graphql-schema.md`「ページングと N+1」）。明細の行の文言は IB-126 |
| 配置 | PostgreSQL のイメージを上げたときの手順 | 正本にある（`deploy/README.md`）。CI と公開の配置の ICU の版が別になりうることは IB-119 |
| 業務の規則 | `context-map.md`「コンテキスト間の関係」の表の「受注 → 在庫」の行に、M50 でメソッド名（`Inventory::Stocks.safety_stocks_sql`）が入った | 確信を持てない。`cycle-end.md`「2. 知見の収穫」5 は業務の規則の文書にクラス名とメソッド名を書かないとするが、同じ表には前から `Inventory::Allocation`・`Inventory::ItemLabels` がある。行を直すか、規則をクラス名まで許すかは、次のサイクルへ送る |

## 見た層

| 層 | 見たもの | 書いた項目 |
|---|---|---|
| 表とマイグレーション | 2 本のマイグレーション、`structure.sql`、`lib/tasks/read_models.rake`、`data-model.md`「文字列の照合順序」と出荷の表、`bin.md` の運用のタスクの表 | `bin.md` の `read_models:rebuild` の行 |
| 公開 API | `Page`・`Page::Sort`、5 つの一覧の公開 API の `order_by:`、`Sales::Catalog`・`Sales::ItemPrices.today_price`・`Sales::SalesOrders.order_numbers`、`Inventory::Stocks.safety_stocks_sql`、`Fulfillment::ShipmentRequests`、ADR 011 | 「読み取りの一覧」の品目の行、ADR 011 の代替案 D |
| policy | diff に変更なし | 無し |
| GraphQL | `Resolvers::SortArguments`、5 つのリゾルバ、2 つの `OrderField`、`schema.graphql`、`graphql-schema.md` の表と SDL | 無し |
| ジョブとイベント | 「出荷可能」の型と `from_payload`、`Sales::OrderAllocation` の発行、出荷の受け手、`data-model.md` のイベントの表、`context-map.md` | 見せどころの `from_payload` の箇条 |
| テスト | `page_spec.rb`、`sort_arguments_spec.rb`、`graphql_matrix_spec.rb`、`collations_spec.rb`、`ci_checks_spec.rb`、`logging_spec.rb`、`read_model_copies_spec.rb`、`demo_world_spec.rb`、request spec と単体の diff、`testing.md` | `testing.md` の写しを足す人への規則 |
| CI と設定 | `.github/workflows/ci.yml`、`config.md`「CI の工程」「照合順序の版」「database.yml」、`bin.md`「CI が使うもの」、ADR 009 | 無し（見せどころへの索引は上の表） |
| 画面 | 5 つの一覧の画面とダッシュボード、`columns.tsx`・`sortable-head.tsx`・`ui/table.tsx`・`kanban-board.tsx`・2 つの詳細、`lib/` の並べ替えと合計と取消の関数、`frontend/graphql/`、E2E の diff | 無し |
| 配置 | `deploy/README.md` の作り直しの段落と「PostgreSQL のイメージを上げたとき」 | 無し |
| 見せどころ・README | `showcase.md` 全体（テーマ 3・4・6・8・9・10）、`README.md` の開発環境・画面・文書の表 | 見せどころの 5 行、README の ADR 011 の説明 |

## 前の形の数え上げ

振る舞いを変えた後の前の形を、`cd585d3` の版で `git grep -F`（`docs/plans/` を除く）で数えた。証跡は書いた時点の記録なので数えない。

| パターン | 件数 | 読み |
|---|---|---|
| `image_inputs` | 12 | すべて `implementation-plan.md`（前提の表の M42・M48 の行、M42 の節、M48 の節）。M42 の節は閉じたマイルストーンの記録なので直さない |
| `!cancelled()` | 3 | 計画の M42 の節 2 か所と、M48 の節の説明。正本とコードに 0 件 |
| `` COLLATE "C" `` | 0 | — |
| `` 照合順序 `"C"` `` | 1 | 計画の M49 の「文書に残すこと」（直す対象の説明） |
| `en_US` | 5 | `data-model.md` の DB の既定の説明（今の形）、計画の M49 の 2 か所、2 つの spec のコメント（言語の照合順序の例。誤りではない） |
| `並べ替えの列は 1 つ` | 1 | 計画の M39 の節で、M47 で `thenBy` を足したと時点を書いてある |
| `同じ列は 昇順 → 降順 → 既定の並び` | 2 | 計画の M47 の「文書に残すこと」と、`frontend/lib/list.test.ts` の、並びが列 1 つの場合の example の名前 |
| `"INBOUND"`（取消依頼の文脈） | 1 | `purchase-order-flow.test.ts` の、入荷予定の発注にボタンを出さないことを確かめる行 |
| `CI は \`npm ls --all\` を流さない` | 0 | — |
| `いまは在庫の品目の写し` | 1 | `guides/bin.md` の運用のタスクの表。古いので上の表で直した（直した後は 0 件） |
