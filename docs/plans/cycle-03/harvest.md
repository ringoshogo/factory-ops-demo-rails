# サイクル 03 の知見の収穫

サイクル 03（M36・M25・M26・M28・M27・M29）の実装で分かったことのうち、正本に無いものを正本へ書いた記録である。手順は `guides/cycle-end.md`「2. 知見の収穫」にある。逸脱検査（`conformance.md`）は、ここで足した正本を含めて成果物と突き合わせる。再発防止（`recurrence.md`）は、ここにある知見を 2 度書かない。

読んだものは、サイクルの diff（`git diff 201290a..4122a39`）、振り返りの想定外（`retrospective.md`）、台帳の `judgment` の行（OI-81〜OI-115）と改善の候補（IB-28〜IB-49）、実装レビューの証跡の「実装の記録」、正本（`architecture/`・`adr/`・`guides/`・`README.md`「開発環境」）である。diff の層ごとの読み取りは、取りまとめ役とも実装者とも別の Claude のサブエージェントに頼み、結果をファイルと行で確かめてから書いた。マイルストーンの中で正本に書き足した分（M25〜M29 の業務の規則、M36 の行列の世界、M28 の非同期の型）は済んでいるので、ここではその漏れを拾った。

## 正本に書いた項目

| 層 | 項目 | 分類 | 正本の状態 | 書いた文書と節・内容 | 根拠 |
|---|---|---|---|---|---|
| 公開 API | 公開 API は役割を確かめないので、GraphQL を通らない入口（ジョブ・rake タスク）から `admin` に限る操作の公開 API を呼ぶ人は、呼ぶ前に同じ規則を評価する | 作り方 | 無い。取り込みの規則の行と OI-109 にだけ、取り込みの形として書いてあった | `architecture/graphql-schema.md`「役割による制限」。規則を評価する場所の段落に、GraphQL を通らない入口の形を足した | `16abc85`・`bc55a6b` |
| ジョブとイベント | 受注が確定したら、受注側の `admin` に新しい受注を撃ちっぱなしで知らせる（OI-83・OI-98） | 満たすこと | 無い。受領請求書の通知は「検収と請求の流れ」にあるが、受注の通知は「発注の連結と品番の照合」に無い | `architecture/context-map.md`「発注の連結と品番の照合」3。知らせを失っても受注一覧で業務が進むこと（B-1）も書いた | `1d0abb6` |
| 公開 API | 受注のコンテキストが販売単価の履歴を所有し、取り込みのパッケージはもうある | 作り方 | 不正確。コンテキストの表の受注の行に単価の履歴が無く、取り込みを「まだ作っていない」と書いていた | `architecture/context-map.md`「コンテキスト」 | `3f60248`・`16abc85` |
| 表とマイグレーション | 「請求書発行」の発行日は、確定の時刻（`issued_at`）の日付である（OI-92） | 満たすこと | 無い。イベントの表に「発行日」とあるだけだった | `architecture/data-model.md`「請求（`billing`）」の確定の表。時刻帯は作者の判断（OI-117）に従うので、ここでは書かない | `89307aa` |
| 公開 API | 一括の取り込みで単価の行を閉じて足すのは、既存の品目の単価が変わる行だけである（OI-110・OI-115） | 決定 | 不正確。「引き受けるコスト」が、取り込みの全行がこの操作を通ると読めた | `adr/006`「引き受けるコスト」1 つ目 | `16abc85`・`36aa1f7` |
| CI と設定 | パッケージが 10 になった。`notifications`・`imports` の行と、`platform` の `ExternalEffectJob`・`ApplicationMailer` | 作り方 | 不正確。「8 つのパッケージ」「`platform` 以外の 7 つ」と書き、表に 2 つの行が無かった | `guides/packs-and-packwerk.md`「packs/ に並ぶもの」「package.yml の項目」 | `e3d49af`・`16abc85` |
| CI と設定 | カスタム Cop `FactoryOps/ExternalEffectEnqueue` | 手順 | 不正確。`bin/rubocop` の行が 2 つの Cop しか挙げていなかった | `guides/bin.md`「コミットの前に流す検査」 | `e3d49af` |
| CI と設定 | 開発で `bin/jobs` が要るのは、イベントのほかに、通知のメール・取り込み・定期のジョブである。ジョブのテナントは、取り込みはチャンクごと、Webhook の受信の処理は行ごとに開く | 手順 | 不正確。イベントのときだけ要ると読め、ジョブは実行全体でテナントを設定すると書いていた | `guides/bin.md`「bin/dev がジョブを処理しないこと」「bin/jobs が接続するロール」。詳しくは `guides/config.md`「ジョブ」を参照させた | `e3d49af`・`8b0607c`・`16abc85` |
| CI と設定 | 運用で流す rake タスク（`sales:backfill_item_prices`・`notifications:redeliver`・`imports:reenqueue`・`audit:purge`・`imports:sample`）の時機・引数・接続 | 手順 | 無い。ADR と `config.md`「ジョブ」と計画に散っていた | `guides/bin.md`「本番のコンテナが使うもの」の下に「bin/rails で流す運用のタスク」を足した | `3f60248`・`e3d49af`・`16abc85` |
| CI と設定 | 環境の 3 ファイルに通知の送信先の設定を足し、本番の SMTP の生成時のコメントを消した | 作り方 | 不正確。「ログの書式と N+1 の検出を足し、使っていない部品の設定を消したほかは生成のまま」と書いていた | `guides/config.md`「環境ごとの設定」 | `e3d49af` |

## 書かなかった項目

| 層 | 項目 | 理由 |
|---|---|---|
| 表とマイグレーション | 販売単価の表（排他制約・CHECK 制約・書き換えを拒むトリガー・経路 1 のポリシー）、受注明細の `priced_on` | 正本にある（`data-model.md`「受注（`sales`）」「RLS」、`adr/006` 決定 1〜3・7） |
| 表とマイグレーション | 請求書の確定・採番・確定した請求書のトリガー・受領請求書（OI-84・OI-88・OI-92） | 正本にある（`data-model.md`「請求（`billing`）」「購買（`purchasing`）」） |
| 表とマイグレーション | 送信記録と受信の表（テナントの表にしない、残す項目、30 日で消す）（OI-96・OI-100） | 正本にある（`data-model.md`「通知（`notifications`）」、`adr/007` 決定 5 の A-3） |
| 表とマイグレーション | 受信の表の DB の説明が「メールアドレスを除いて生のまま残す」で、実装と `data-model.md`（処理に使う項目だけ）に合わない | 収穫ではなく、どちらが正かの裁定が要る。逸脱検査に回す |
| 表とマイグレーション | 取り込みの 3 つの表・CSV の契約・失敗の理由（OI-82・OI-111・OI-113） | 正本にある（`data-model.md`「取り込み（`imports`）」） |
| 表とマイグレーション | `Sales::Item` の `ignored_columns` を残す・列を消すマイグレーションが移行の前に止まる（OI-106）、取り込みの種類の CHECK 制約を `text` にして比べる | 実装の手段。理由はモデルとマイグレーションのコメントにあり、`bin/check-structure` が守る |
| 表とマイグレーション | `items.unit_price` を消すときのデプロイの順 | 改善の候補 IB-42 にある |
| 公開 API | `saveItem` の単価の扱い・記録の時刻・同じ単価の予約（OI-89・OI-103・OI-104・OI-108） | 正本にある（`graphql-schema.md`「mutation の一覧」、`adr/006` 決定 3・4） |
| 公開 API | 取り込みの反映の順・チャンクのロック・置き場へ写す読み方（OI-110・OI-112・OI-115） | 正本にある（`data-model.md`「取り込み（`imports`）」、`adr/007` 決定 5 の A-4）。1 MB ずつ写すことは実装の手段 |
| 公開 API | 操作者を取らない公開 API（`Partnerships::Recipients`・`Notifications::Email`・`Imports::Runs.reenqueue` など）がある | 収穫ではない。`graphql-schema.md`「認可」は「操作者を渡さずにレコードを返す公開 API は作らない」「scope は RLS に任せない」と例外なく書き、`Recipients.admin_ids` は RLS だけで絞る。どちらが正かの裁定が要るので、逸脱検査に回す |
| 公開 API | 同じ値（単価・公開の状態）を書く入口がすべて同じ規則を通る、という一般の規則 | 確信を持てない。いまの正本は単価だけを個別に決め、新しい品目の最初の単価と公開の状態は、`saveItem`・`setItemPublished`（役割を問わない）と品目の CSV（`admin`）で規則が違う。一般の規則にするなら業務の振る舞いが変わりうるので、正本に書かない。入口を数えることは、再発防止で計画レビューの手順に入れる |
| 公開 API | 出荷停止と出荷可能の受注 ID ごとのアドバイザリロック（OI-79）、ダッシュボードの集計の境界（OI-81・OI-93・OI-94）、複雑度の数え方（OI-95） | 正本にある（`data-model.md`「出荷（`fulfillment`）」、`graphql-schema.md`「読み取りの一覧」「明示的な例外と列挙テスト」「ページングと N+1」） |
| 公開 API | 登録口・再試行を登録し直す形・再送の対象・再試行する例外（OI-97・OI-99・OI-102） | 正本にある（`adr/007` 決定 4・5）。例外の並びは実装の手段 |
| 公開 API・ジョブ | 業務の日付の時刻帯（受注日・検収日・単価の有効日は UTC、ダッシュボードの今日だけ日本時間） | 業務の振る舞いが変わる判断なので、正本に書かず、作者の判断 OI-117 に積んだ（`inventory.md`） |
| policy | 役割の制限の表、受領請求書の規則に発注の policy を使う（OI-92）、行列で `member` の行も `member` で呼ぶ（OI-90・OI-107） | 正本にある（`context-map.md`「自社の中の役割」、`graphql-schema.md`「役割による制限」）。発注の policy を使うことは実装の手段 |
| GraphQL | 新しい型と mutation、ダッシュボードを認可の例外にする（OI-93）、ファイルの受け口と Webhook の受け口 | 正本にある（`graphql-schema.md` の SDL・一覧・例外の表、`config.md`「CSRF を防ぐ前提」「routes.rb で足したもの」）。SDL と `schema.graphql` の一致は逸脱検査で照らす |
| GraphQL | 公開 API のソースの引数のまとめ方、クエリ数の予算のガード | 実装の手段。ソースのコメントと spec にある |
| ジョブとイベント | 外部へ作用するジョブの宣言と Cop、キュー 4 つ、`limits_concurrency`、定期のジョブ、`tenant_transaction :per_chunk`、Continuable、ログのイベント | 正本にある（`adr/007` 決定 4・5・7、`config.md`「ジョブ」「イベントごとに書く項目」）。TracePoint の形は IB-39 |
| ジョブとイベント | inbox の 1 バッチ・ロックの内側で HTTP を呼ぶ・本番の API キーの空・テナントの無い競合テスト・ファイルの受け口のログの文脈 | 改善の候補 IB-36〜IB-40・IB-49 にある |
| テスト | 行列の世界をファイルごとに作る・後始末のガード・request spec の補助・`spec/notifications` の層・ロックの表の行 | 正本にある（`testing.md`「行列テストとの分担」「競合テスト」「層への配分」「テストの層」） |
| テスト | WebMock で外部への HTTP を止めること、テストの送信先 | 正本にある（`config.md`「ジョブ」） |
| テスト | パッケージの中の置き場（`app/jobs`・`app/mailers`・`spec/db`）と、DB の制約の spec が `packs/sales/spec/db`（単体の層）と `spec/db`（ガードの層）に割れていること | 確信を持てない。置き場の規約にするか、例のままにするかを決める材料が 2 件しか無い。次のサイクルへ送る |
| テスト | 上限ちょうどと上限 + 1 を仕様の値で書く、`WITH CHECK` だけを緩めても表の行列が落ちない、世界のトランザクションの閉じ方 | 改善の候補 IB-25・IB-30・IB-31 にある。IB-25 は改善の探索で、IB-30 は再発防止で扱う |
| CI と設定 | `queue.yml`・`recurring.yml`・通知の初期化・`application.rb` の 2 つの `x` の設定・credentials の 2 つの鍵・routes の 2 本・`FRONTEND_ORIGIN`、Gemfile の csv・webmock | 正本にある（`config.md` の一覧・「ジョブ」・「application.rb で変えたこと」・「routes.rb で足したもの」）。gem の理由は Gemfile のコメントにある |

## 見た層

| 層 | 見たもの | 書いた項目 |
|---|---|---|
| 表とマイグレーション | 5 本のマイグレーションとコメント、`structure.sql` の表の説明、`data-model.md` の「全テーブルに共通の規則」「受注」「請求」「通知」「取り込み」「RLS」 | 発行日 |
| 公開 API | `Sales::Catalog`・`ItemPrices`・`PartMatching`・`PublishedCatalog`、`Billing::Closing`、`Imports::Runs`・反映、`Notifications::Email`、`Partnerships::Recipients`・`Authentication.acting_user`、`Fulfillment::SalesEventReceiver`、`context-map.md`・`adr/006` | GraphQL を通らない入口の規則、コンテキストの表、ADR 006 のコスト |
| policy | `ItemPolicy`・`ImportPolicy`・`InvoicePolicy`・`PurchaseOrderPolicy`・`SalesOrderPolicy` と scope の差分、`graphql-schema.md`「認可」「役割による制限」、`context-map.md`「自社の中の役割」 | 無し（一般の規則は書かなかった） |
| GraphQL | ダッシュボードのリゾルバと型、公開 API のソース、2 つのコントローラ、`graphql-schema.md` の一覧と例外とページング | 無し |
| ジョブとイベント | `ApplicationJob`・`ExternalEffectJob`・`Imports::RunJob`・イベントのキュー・配送表、`adr/007`、`config.md`「ジョブ」「ログ」、`bin.md`「bin/jobs」 | 新しい受注の通知、`bin/jobs` の要る場面とテナントの開き方 |
| テスト | `spec_helper`・`rails_helper`・`spec/support` の補助、ロックの表・テナントの列・表の説明・キューの設定・外部の HTTP の spec、`config/test_layers.yml`、`testing.md` | 無し |
| CI と設定 | `.rubocop.yml`・Gemfile・`application.rb`・環境の 3 ファイル・初期化・`queue.yml`・`recurring.yml`・routes・`lib/tasks/` の rake タスク、`config.md`・`bin.md`・`packs-and-packwerk.md`・README「開発環境」 | パッケージの一覧、Cop の一覧、環境の設定、運用の rake タスク |
