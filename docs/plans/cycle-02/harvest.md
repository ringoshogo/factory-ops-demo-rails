# サイクル 02 の知見の収穫

サイクル 02（M34・M35・M21〜M24）の実装で分かったことのうち、正本に無いものを正本へ書いた記録である。手順は `guides/cycle-end.md`「2. 知見の収穫」にある。逸脱検査（`conformance.md`）は、ここで足した正本を含めて成果物と突き合わせる。再発防止（`recurrence.md`）は、ここにある知見を 2 度書かない。

読んだものは、サイクルの diff（`git diff 5f67a8e..0088cb6`）、振り返りの想定外（`retrospective.md`）、台帳の `judgment` の行（OI-59〜OI-76）、実装レビューの証跡の「実装の記録」、正本（`architecture/`・`adr/`・`guides/`・`README.md`「開発環境」）である。diff の層ごとの読み取りは、取りまとめ役とも実装者とも別の Claude のサブエージェントに頼み、結果をファイルと行で確かめてから書いた。マイルストーンの中で正本に書き足した分（M21〜M24 の業務の規則、M34・M35 の設定と検査）は済んでいるので、ここではその漏れを拾った。

## 正本に書いた項目

| 層 | 項目 | 分類 | 正本の状態 | 書いた文書と節・内容 | 根拠 |
|---|---|---|---|---|---|
| 公開 API | 請求のパッケージにコードがある | 作り方 | 不正確。`billing` の行が「まだ `package.yml` だけ」のまま | `guides/packs-and-packwerk.md`「packs/ に並ぶもの」。中身を請求条件・請求対象明細・請求書にし、公開 API の例を `Billing::Closing`・`Invoices` にした | `c901022` |
| CI と設定 | 依存の向きの表と `package.yml` の一致を確かめる spec（OI-58） | 作り方 | 無い。境界の検査の表が 4 つのまま | `guides/packs-and-packwerk.md`「CI で落ちる場所」。`spec/packwerk/dependency_table_spec.rb` の行を足し、5 つにした | `e89cf83` |
| ジョブとイベント | 購買から受注へのイベントの受け手が 2 つに分かれた | 満たすこと | 不正確。ACL を `Sales::PurchaseOrderTranslator` 1 つと書いていた | `architecture/context-map.md`「コンテキスト間の関係」の購買 → 受注の行。「発注登録」と「取消依頼」「検収完了」の受け手を書き分けた | `d98b093`・`f407442` |
| 公開 API | 発注側の取消の理由は購買に残すだけで、受注側の審査には届かない（OI-68） | 満たすこと | 無い。理由の長さと、イベントが理由を運ばないことはあるが、受注側の担当者が理由を見ずに審査する業務の事実が無い | `architecture/context-map.md`「取消の流れ」1 | `d98b093` |
| 表とマイグレーション | 破棄した下書きを残さない理由（OI-75） | 決定（ADR にしない。行の中に理由を 1 文） | 無い。消すことだけがあり、残さない理由はコードにも無い | `architecture/data-model.md`「請求（`billing`）」の破棄の段落 | `c901022`・`081d7cc` |
| 公開 API | 公開 API のモジュールは、同じパッケージのモデルと同じ名前にできない（OI-72） | 作り方 | 無い。計画が単数の名前を付け、実装でモデルとぶつかって複数形に直した | `guides/packs-and-packwerk.md`「公開 API を出す」に「名前」の項を足した | `2a8eb91`・`f407442` |
| CI と設定 | 環境の設定から Active Storage の行と Action Cable のコメントを消した | 作り方 | 不正確。`environments/` を「ログと N+1 のほかは生成のまま」と書いていた | `guides/config.md`「環境ごとの設定」 | `4256113` |
| CI と設定 | CI の配線（ステップと `BASE_REF` の式、`config/ci.rb` の工程）を spec で守らない（OI-59） | 決定（行の中に理由を 1 文） | 無い。台帳にだけあり、M35 で test のジョブの `BASE_REF` も同じ形になった | `guides/config.md`「CI の工程」。式を文字列で照らす spec は書き換えに追従できないので書かず、配線を変えた PR で落ちることを手で確かめる | `bf70626`・`2482ca2` |
| テスト | 分岐の網羅率の警告の件数を証跡に書き、振り返りで合計して評価する | 手順 | 不正確な置き場。作り方の `guides/testing.md` にだけあり、回し方の文書に無かった | `guides/dev-cycle.md`「実装レビュー」（証跡に残すもの）と `guides/cycle-end.md`「1. 振り返り」4 に書き、`guides/testing.md`「分岐の網羅率の警告」は参照にした | `528a5c9`・`81cacea` |

## 書かなかった項目

| 層 | 項目 | 理由 |
|---|---|---|
| 表とマイグレーション | 取消・検収・請求の表・CHECK 制約・一意索引、請求書と明細の複合外部キー | 正本にある（`data-model.md`「購買（`purchasing`）」「受注（`sales`）」「出荷（`fulfillment`）」「請求（`billing`）」） |
| 表とマイグレーション | 解除前の出荷停止に部分一意索引を置かない（OI-67）、締め日に 29・30 を許さない、数量 0 の明細に請求対象確定を出さない（OI-74） | 正本にある（`data-model.md`、`context-map.md`「検収と請求の流れ」3）。理由はマイグレーションのコメントにもある |
| 公開 API | 取消・受注側の取消・検収の操作と状態の組みごとの結果（OI-60・OI-62・OI-63） | 正本にある（`context-map.md`「取消の流れ」「検収と請求の流れ」） |
| 公開 API | 締めの確かめる順・期間の決め方・請求番号を確定で振る・受け手がロックしない・破棄のロック（OI-64・OI-66） | 正本にある（`data-model.md`「請求（`billing`）」） |
| 公開 API | 自動の却下で「取消却下」が 2 回出る（OI-70） | 正本にある。購買の受け手は回答が空のときだけ書く（`data-model.md`「イベントの受け口と冪等キー」）。見せ方は IB-23 |
| 公開 API | `cancelSalesOrder` が理由を取らない（OI-71）、3 つの mutation の戻り値（OI-69・OI-73） | 実装の手段。`schema.graphql` の入力型と戻り値の型から読める |
| policy | 取消・検収・請求の規則が役割を問わない | 正本にある（`graphql-schema.md`「役割による制限」）。役割を問わないことの是非は作者の判断に回す（`inventory.md`） |
| GraphQL | 新しい型、`invoiceNumber` が空を許す、監査の表、`audit_exempt`、入力の上限 | 正本にある（`graphql-schema.md`）。`schema.graphql` と一致した |
| GraphQL | `supplier.invoices` に `InvoiceFilter` を作らない（OI-76） | 収穫ではなく、正本の SDL と実装のどちらが正かの裁定が要る。逸脱検査に回す |
| ジョブとイベント | 付帯情報の無いイベントのジョブを失敗させる（OI-61）、届く順の入れ替わり、宛先テナントを運ぶ | 正本にある（`guides/config.md`「相関 ID と因果 ID」、`data-model.md`「イベントの届く順の入れ替わり」） |
| テスト | `deliver_enqueued_events(newest_first:)`、締めの最中の検収の競合テストの書き方 | 実装の手段。補助のコメントと `spec/jobs/deliver_enqueued_events_spec.rb` から読める |
| テスト | bootsnap が古い版を読む（IB-24）、上限ちょうどの example（IB-25）、後始末のガード（IB-26） | 改善の候補の台帳にある。IB-24 は再発防止で扱う |
| CI と設定 | bundler 2.5.3 で net-pop の依存が落ちる | 改善の候補 IB-18 にある |
| CI と設定 | Ruby 3.4.11・外した部品・許した一覧のログの spec・分岐の網羅率の警告・CI の test のジョブ | 正本にある（`guides/config.md`・`guides/bin.md`・`guides/testing.md`・ADR 008）。ファイルと照らして一致した |
| 全層 | 消した・外したことの理由がコードに残っていない箇所（`config/application.rb` の外した部品、スキーマの `extra_types`） | 知見ではなく、作者の要望が規約に無かったことによる。振り返りから再発防止に渡す |

作者の判断 OI-24・OI-58 は、`config/test_layers.yml`・`guides/testing.md`・`spec/bin/test_layers_spec.rb`・`implementation-plan.md` M16、`context-map.md`「疎結合を守る規則」・`package.yml`・M28・M29 と食い違いが無かった。漏れは、上の表の `guides/packs-and-packwerk.md` の検査の表だけである。

## 見た層

| 層 | 見たもの | 書いた項目 |
|---|---|---|
| 表とマイグレーション | 取消・検収・請求の 3 つのマイグレーションとコメント、`data-model.md` の差分と「RLS」 | OI-75 |
| 公開 API | 請求・受注・購買の公開 API と受け手、在庫と購買の公開 API の名前 | 請求のパッケージ、OI-68、OI-72 |
| policy | `Billing::InvoicePolicy`・`Billing::Scope`・受注と購買の policy の差分、`graphql-schema.md`「認可」 | 無し |
| GraphQL | `schema.graphql`、`graphql-schema.md` の SDL・監査の表・mutation の一覧・「ページングと N+1」、宣言の spec の例外の一覧 | 無し（OI-76 は逸脱検査へ） |
| ジョブとイベント | `Contracts::EventJob`・配送表・受け手の冒頭のコメント、`config.md`「相関 ID と因果 ID」、`context-map.md` の関係の表 | ACL の受け手 |
| テスト | spec の追加と変更、`spec/support`、`testing.md` | 警告の件数の置き場 |
| CI と設定 | `ci.yml`・`config/ci.rb`・`branch_coverage.yml`・`test_layers.yml`・`application.rb`・環境の設定・Gemfile・Dockerfile・除外の設定・`bin/check-branch-coverage`・`bin/test-layers`、`config.md`・`bin.md`・README「開発環境」 | 環境の設定、OI-59、依存の向きの spec |
