# サイクル 10 の知見の収穫

サイクル 10（M57・M54 の残り）の実装で分かったことのうち、正本に無いものを正本へ書いた記録である。手順は `guides/cycle-end.md`「2. 知見の収穫」にある。逸脱検査（`conformance.md`）は、ここで足した正本を含めて成果物と突き合わせる。再発防止（`recurrence.md`）は、ここにある知見を 2 度書かない。

読んだものは、サイクルの diff（`git diff aba5836..7b03877`）、振り返りの想定外（`retrospective.md`）、改善の候補（IB-144・IB-145・IB-150〜IB-152・IB-154）、実装レビューの証跡の「実装の記録」、正本（`architecture/`・`adr/`・`guides/`・`README.md`・`showcase.md`・`deploy/README.md`・`handoff.md`）である。サイクルの diff は `docs/` を除いて 20 ファイル・+253／−61 行と小さいので、層ごとの読み取りは取りまとめ役の側で行った。マイルストーンの中で正本に書き足した分（`guides/config.md` の `publish` の `if:` の一致の形と全件の印と `ignored_columns` の 3 つの規則、`guides/testing.md` の全件の印、`guides/packs-and-packwerk.md` の GraphQL の enum に写す一覧、`guides/bin.md` の `test` の行、ADR 011 の写しの理由、ADR 012 決定 4 と `data-model.md` の出荷指示の取消のロックの順、`graphql-schema.md` と `showcase.md` のテーマ 3 の写しの理由、テーマ 8・10 の M57 の行）は済んでいるので、ここではその漏れを拾った。

漏れは、サイクル 06〜09 と同じく見せどころ（`showcase.md`）だった。M54 の残りで設計文書に書いた 2 つ（出荷指示の取消のロックの順と、列を消した後の `ignored_columns` の規則）が、どのテーマにも無かった。

## 正本に書いた項目

| 層 | 項目 | 分類 | 正本の状態 | 書いた文書と節・内容 | 根拠 |
|---|---|---|---|---|---|
| 表とマイグレーション | 出荷指示の取消は受注をロックせずに出荷依頼 → 出荷指示の順に取り、計上の順の部分列なのでデッドロックを起こさないこと | 作り方 | 無い。規則は ADR 012 決定 4 と `data-model.md`「取消と出荷の競合を止める場所」にあり、見せどころのテーマ 4 の「ロックの順」の箇条は出荷指示の作成と計上の順だけを書いていた | `showcase.md`「4. 整合性の設計」のロックの順の箇条に 2 文（部分列であることと、受注の取消と同じ行を取らないこと）、状態に M54 の残り | `6684056` |
| 表とマイグレーション・配置 | 列を消す変更は `ignored_columns` に入れて同じ変更で消し、外すのは消すマイグレーションが main に入った後の別の PR にすること。間の版を飛ばしたときの壊れを毎日の作り直しで許すこと。spec が列を足し直すあいだは外さないこと | 作り方 | 無い。規則は `guides/config.md`「initializers/strong_migrations.rb：危険なマイグレーションを止める」にあり、見せどころのテーマ 10 の公開の配置の箇条に無かった | `showcase.md`「10. 運用性」に箇条 1 つ、状態に M54 の残り | `6684056`・`7af34f9` |

## 書かなかった項目

| 層 | 項目 | 理由 |
|---|---|---|
| 表とマイグレーション | `Fulfillment::ShipmentRequest` の `cancelled_at` の無視を外し、`Sales::Item` の `unit_price` の無視を残したこと | 正本にある（`guides/config.md` の規則 2・3）。どの列に当てたかはモデルのコメントとコードが語る |
| 表とマイグレーション | マイグレーションのコメント 2 か所を、規則の文と ADR 011 を指す文にしたこと | 実装レビューの直し（M54 の残りの Claude R2）で、正本は変えていない |
| 公開 API | 状況・進みの種類・在庫移動の一覧を、公開 API に同じオブジェクトを指す定数の別名で出したこと | 正本にある（`guides/packs-and-packwerk.md`「公開 API を出す」の GraphQL の enum に写す一覧）。別名の名前は実装の手段 |
| GraphQL | スキーマのすべての enum の型を、公開 API の定数と値の集合で比べるか、理由付きで比べない表に載せること。比べない 8 個の理由 | 正本にある（`packs-and-packwerk.md`、`showcase.md` のテーマ 8 の表）。比べない理由は `spec/graphql/enum_values_spec.rb` の表にあり、その型を変える人がそこで読む。`graphql-schema.md`「状況の enum」にも同じ規則を書くと、作り方の 2 か所に同じ規則が並ぶので書かない |
| GraphQL | `extra_types` で足した enum の型は `FactoryOpsSchema.types` に載らず、一致の spec の外になること | スキーマは `extra_types` を使わないと決めていて（`app/graphql/factory_ops_schema.rb` のコメント）、spec の型を集める `let` のコメントにも書いた。使わない道具の振る舞いなので、正本に書かない |
| GraphQL | `Page::Sort::DIRECTIONS` を `Data.define` のブロックの外に置くこと | 実装の手段。ブロックの中の定数が外側に付くことは Ruby の言語の振る舞いで、コードを読めば分かる |
| テスト | 全件の印 `FULL_SUITE=1` で呼ばれない公開 API を落とすこと。判定を子のプロセスで確かめるガードの example | 正本にある（`guides/testing.md`「層への配分」、`guides/config.md`「CI の工程」の工程の表、`guides/bin.md`、`showcase.md` のテーマ 8）。子のプロセスの spec の置き場と `COVERAGE` を渡さない理由は、`spec/platform/public_api_returns_spec.rb` と `spec/fixtures/public_api_returns/one_example.rb` にある |
| テスト | 移行の spec の、列を読ませてから消しても品目を作れる example | 上の「正本に書いた項目」の 2 行目で、見せどころのテーマ 10 から指した。example の書き方は実装の手段 |
| CI と設定 | `publish` の `if:` を 1 つの式に一致させて照らすこと。式を変える人がすること | 正本にある（`guides/config.md`「CI の工程」、`showcase.md` のテーマ 8・10） |
| 画面 | `list-pagination.spec.ts` のコメントを、写しで並ぶことと写しが受注と食い違えば並びが崩れることを書く、いまの契約の短い文にしたこと | コメントの直しで、画面の振る舞いは変わらない（逸脱検査の違和感で、この行の「ADR 011 を指す文にした」を実物に合わせて直した） |
| 配置 | 規則 2 の割り切りと公開の配置の関係 | 上の「正本に書いた項目」の 2 行目で、見せどころのテーマ 10 に書いた。`deploy/README.md` は、作者が流す手順の文書で、列を消す PR の分け方は手順に入らないので書かない |
| 引き継ぎ | `handoff.md`「次にやること」と「ブランチ」 | 知見ではなく引き継ぎの更新で、台帳の棚卸しでサイクル 10 の終わりの形に直す（`inventory.md`） |

## 見た層

| 層 | 見たもの | 書いた項目 |
|---|---|---|
| 表とマイグレーション | 2 つのマイグレーションのコメント、`shipment_request.rb`・`item.rb` の `ignored_columns`、`structure.sql`（変更なし）、ADR 011・ADR 012、`data-model.md`、`guides/config.md` | 見せどころのテーマ 4・10 |
| 公開 API | `Purchasing::PurchaseOrders`・`Sales::SalesOrders`・`Fulfillment::ShipmentRequests`・`Inventory::Stocks` の定数の別名、`Page::Sort::DIRECTIONS`、`packs-and-packwerk.md` | 無し |
| policy | 変更なし | 無し |
| GraphQL | `spec/graphql/enum_values_spec.rb`、`graphql-schema.md`「状況の enum」、スキーマの `extra_types` のコメント | 無し |
| ジョブとイベント | 変更なし。`read_models.rake` の作り直しのタスクのコメント | 無し |
| テスト | `public_api_returns.rb`・`rails_helper.rb` の `after(:suite)`、`public_api_returns_spec.rb`、`ci_checks_spec.rb`、移行の spec、`testing.md` | 無し |
| CI と設定 | `.github/workflows/ci.yml`、`config/ci.rb`、`config.md`、`bin.md` | 無し |
| 画面 | `frontend/e2e/list-pagination.spec.ts` のコメント | 無し |
| 配置 | `deploy/README.md`（変更なし） | 無し |
| 見せどころ・README・引き継ぎ | `showcase.md` 全体、`README.md` の開発環境の `bundle exec rspec`（全件の印を渡さない手元の実行で、落とさない形のままでよい）、`handoff.md` | 見せどころの 2 か所。`handoff.md` は棚卸しで直す |

## 前の形の数え上げ

振る舞いを変えた後の前の形を、`7b03877` の版で数えた（`docs/plans/` を除く。証跡は書いた時点の記録なので数えない）。件数は当たった行の数である。

| パターン | 件数 | 読み |
|---|---|---|
| `success_inside_call`・`without_strings` | 0 | M57 の完了条件（`docs/implementation-plan.md` を除く） |
| `format('{0}', success())`（`docs/guides`・`docs/showcase.md`・`.github`） | 0 | M57 の完了条件 |
| `写しを作った時点`・`依存しなかった`・`依存の向きを変えずに`（`docs/adr` と計画を除く） | 0 | M54 の残りの完了条件 |
| `出荷依頼の行だけをロック`・`受注を読まずに` | 0 | M54 の残りで直した「出荷（`fulfillment`）」の前の文 |
| `ignored_columns`（`packs`） | 1 | `Sales::Item` の `unit_price`。規則 3 で残す |
| `比べる 10`・`比べない 9` | 1 | 台帳の OI-230 の行（後ろに OI-235 で変えたことを書いてある）。正本とコードに 0 件 |
