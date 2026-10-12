# 引き継ぎ：作業の現在地と次の一手

新しいセッションで作業を再開する人（Claude を含む）が最初に読む文書。プロジェクトの目的、決まったこと、決まっていないこと、次にやることを示す。

## 目的

このリポジトリは、作者が Rails のアーキテクトとして設計判断できることを示すポートフォリオである。見せたいのは動く機能の多さではない。設計判断（`architecture/decisions.md`）が、コードのどこで、どの仕組みで守られているかを読み手が辿れることである。

実装の優先順位はこの目的で決める。見せどころの一覧は `showcase.md` にある。

一方、フロントエンドは見せどころではない。姉妹プロジェクト `factory-ops-demo` の Next.js を流用し、画面部品をそのまま使い、データ取得層を GraphQL に書き換え、発注側の画面を足す。

## 読む順

1. `../README.md`：構成の要約
2. `showcase.md`：見せどころ。何を示したいかと、それを守るコード・テスト・実装の状態
3. `architecture/context-map.md`：業務の流れと 6 つのコンテキスト、つなぎ方、品番照合・取消・検収と請求の流れ、取引関係の失効、許可する依存の向き、テナントの所有、自社の中の役割
4. `architecture/data-model.md`：テナントの持ち方、状態の導出、各コンテキストのテーブル、取消と出荷の競合の止め方、イベントの冪等キー、RLS
5. `architecture/graphql-schema.md`：GraphQL の型を視点ごとに分ける形、相手側へたどれないことの保証、認可の基底クラス、クエリと mutation が呼ぶ公開 API
6. `architecture/decisions.md`：設計判断の一般原則。各論点の既定の推奨と裏返る条件
7. `adr/`：本デモで下した個別の判断
8. `implementation-plan.md`：実装の順番。マイルストーンの一覧と、各マイルストーンの完了条件。実装を始める人は、着手するマイルストーンの節と、そこが挙げる設計文書の節を読む
9. `guides/dev-cycle.md`：開発の回し方。サイクル・レビュー・残件の台帳。作業を再開する人は、着手の前に読む
10. `guides/`（必要なときに）：`bin/`・`config/`・`packs/` と packwerk の解説。Rails の生成物から何を変えたか、packwerk の違反をどう読んで直すかを知りたいときに読む背景。コードにコメントを書く人は `guides/comments.md` を、テストを足す人は `guides/testing.md` を先に読む

`decisions.md` は一般論で、完全分離型のマルチテナントも扱う。本デモに当てはめた結果は `context-map.md`・`data-model.md`・`graphql-schema.md`・`adr/` にある。両者が食い違う場合は `adr/` が優先する。

## 決まったこと

| 項目 | 決定 | 根拠 |
|---|---|---|
| 題材 | factory-ops-demo と同じく、架空の機械部品メーカー「青嵐精機工業」の受発注・在庫管理 | ユーザー判断 |
| マルチテナント | 相互アクセス型。発注側と受注側が同じシステムを使い、発注が相手の受注に連結する | ユーザー判断、`context-map.md` |
| コンテキスト | 取引関係・購買・受注・在庫・出荷・請求の 6 つ＋イベント置き場 `contracts` | `context-map.md` |
| 発注側からの取消 | 可能。受注側の承認が要る。審査の間は出荷を止める | ユーザー判断、`context-map.md`「取消の流れ」 |
| 品番 | 発注側は自社品番で発注する。受注側の腐敗防止層が対応表で読み替える | ユーザー判断、`context-map.md`「発注の連結と品番の照合」 |
| 検収と請求 | 検収の結果を「検収完了」で受注側へ返す。受注側が検収数量 × 受注単価で取引先ごとに月次で締めて請求書を発行し、発注側は「請求書発行」で届いた写しを閲覧する。入金消込は範囲外 | ユーザー判断、`context-map.md`「検収と請求の流れ」 |
| 役割 | 取引関係を変える操作、取消依頼・取消の審査・受注側の取消、検収、請求条件の設定・締め・下書きの破棄・請求書の確定、単価の改定の予約と訂正・品目の CSV の取り込みは `admin` に限り、日常の業務は役割を問わない。Action Policy の操作ごとの規則で判定する | ユーザー判断、`context-map.md`「自社の中の役割」 |
| 取引関係の失効 | 読む 3 経路と新しい発注は閉じる。「発注登録」を出し終えた取引は請求まで進む | ユーザー判断、`context-map.md`「取引関係の失効」 |
| 構成 | Rails（API モード）＋PostgreSQL＋GraphQL。フロントは factory-ops-demo の Next.js を流用 | ユーザー判断 |
| スキーマ管理 | Rails マイグレーション＋`structure.sql`。ridgepole は使わない | `adr/001` |
| 主キー | UUIDv7 を DB の `uuidv7()` で作る。PostgreSQL 18 以降を使う | `adr/003` |
| データモデル | 全テーブルに `owner_tenant_id`、親子は複合外部キー、状態は時刻列から導出、引当は在庫だけが持つ。RLS の `WITH CHECK` は全表で所有テナントに限り、読む 3 経路にだけ SELECT のポリシーを足す | `architecture/data-model.md` |
| DB ロール | 所有ロール `factory_owner`（表の所有者、`BYPASSRLS`）とアプリのロール `factory_app`（一般ロール）に分ける。アプリ・テスト・ワーカーは `factory_app` で接続し、権限は DB のタスクの後に rake タスクで付与する。`tenants` への書き込みは追加だけを許す。本番では所有ロールの資格情報をマイグレーションの工程にだけ渡し、Web とワーカーには渡さない | `implementation-plan.md` M3、`architecture/data-model.md`「RLS」 |
| 境界の強制 | 初日から `packs/` 構成。packwerk の依存チェックとプライバシーチェックを CI で強制する | ユーザー判断、`adr/002` |
| イベントの配送 | Solid Queue を業務 DB と同じ接続に置き、イベントのジョブは業務のトランザクションの中で登録する（`Contracts::EventJob` は `enqueue_after_transaction_commit = false`、それ以外の `ApplicationJob` は `true`）。outbox は置かない。登録は `Contracts.publish` が配送表 `Contracts::Subscriptions` の受け手ごとに行い、受け手は宛先テナントの名義で冪等に処理する。キューの接続が同じであることをテストで固定する | `adr/005` |
| テスト | RSpec＋FactoryBot。設計文書がガードテストを `spec/` のパスで定めているため | `implementation-plan.md`「環境」 |
| 基盤パッケージ | `packs/platform` を足し、`ApplicationRecord`・`ApplicationJob`・`Current`・`Tenancy` を置く。基底クラスをルートパッケージに置くと、パッケージからルートへの依存が循環になるため | `implementation-plan.md` M2 |
| GraphQL | graphql-ruby と Action Policy。1 つのスキーマで `buyer`・`supplier` の入口を分け、型に視点を宣言させて到達可能性をテストで固定する。汎用の `node` は置かない。基底の型・リゾルバ・mutation は宣言が無ければ拒否する | `architecture/graphql-schema.md`、`adr/004` |
| マイルストーンの順 | 残りの業務機能（M21〜M26）の前に、横断の仕組み（M15〜M20：コメントの規約・テストの層・N+1 の検出・構造化ログ・監査ログ・スキーマの差分検査）を入れる。見せどころ（M27〜M31：バイテンポラル・非同期の型・取り込み・メトリクス・SLO）は業務機能の後に足す | `implementation-plan.md`「マイルストーンの一覧」 |
| 販売単価 | 有効期間（`daterange`）と記録期間（`tstzrange`）の 2 軸で持つ。現在の行の有効期間の重なりを排他制約で止め、行は書き換えない。受注は受注日の単価を写す。既存の品目の単価を変えるのは、`admin` に限る改定の予約と訂正だけで、品目の登録からは変えない | ユーザー判断、`adr/006` |
| 業務の日付 | 受注日・検収日・請求書の発行日などの業務の今日を、すべて日本時間で決める（`config.time_zone` を `Asia/Tokyo`）。既存の行は書き換えない | ユーザー判断、`context-map.md`「検収と請求の流れ」 |
| 操作者のいない入口 | ジョブ・rake タスク・イベントの受け手・認証から呼ぶ公開 API は操作者を取らず、テナントの設定を求め、所有の条件を明示し、レコードではなく値を返す。架空のシステムの操作者は作らない | ユーザー判断、`architecture/graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」 |
| 非同期処理の型 | ジョブを失ったときに誰も気づけない処理だけを、トランザクションの中で登録する。型は記録してから処理する A-1 イベント・A-2 確実な外部送信・A-3 inbox・A-4 再開できる長時間のジョブと、記録しない B-1 撃ちっぱなし。外部への作用の重複は C-1〜C-3 から選ぶ。outbox は置かない。外部への作用は `ExternalEffectJob` を継承し、登録口を 1 つにする。テストと開発で本物の SendGrid を呼ばない | `adr/007` |
| ログ | `Rails.event` を出口にした 1 行 1 件の JSON。相関 ID と因果 ID をイベントの付帯情報で運び、テナントをまたぐ一連の処理を引けるようにする。ペイロードに個人情報と自由記述を入れない | `implementation-plan.md` M18、`guides/config.md`「ログ」 |
| 監査ログ | 相手テナントに効果が及ぶ書き込みを、mutation とイベントのジョブの基底クラスが記録する。追記だけで、自社の `admin` が `viewer.auditLogs` で読む | `implementation-plan.md` M19、`architecture/data-model.md`「監査ログ（`platform`）」 |
| テストの層とシナリオ | 単体を厚くし、層ごとの件数を CI で報告する。壊れると事故になる 5 つの流れ（S1〜S5）を、専用のシナリオテストにする。N+1 は Bullet とクエリ数の予算で落とす | `guides/testing.md`、`implementation-plan.md` M17 |
| GraphQL のスキーマの変更 | `schema.graphql` を commit し、非推奨を経ない破壊的変更を、CI の lint のジョブで `bin/check-schema-compat` が落とす | `architecture/graphql-schema.md`「スキーマの変更と非推奨」 |
| メトリクス | Yabeda と Prometheus。値は `Rails.event` から作り、ラベルにテナントとユーザーを入れない | `implementation-plan.md` M30 |
| コードのコメント | いまの振る舞いと理由だけを書き、経緯・マイルストーンの番号・予定を書かない。Cop で止める | `guides/comments.md` |
| 拡張の進め方 | 横断の仕組み（M15〜M20）を業務の残り（M21〜M26）より先に入れる。監査ログの保存期間（7 年）と SLO の値は仮置きのまま進め、値より決め方と測り方を示す。発注側に単価の改定予定は見せない。取り込みは失敗した行だけを報告し、正常な行は反映する | ユーザー判断、`implementation-plan.md` |

## 決まっていないこと

- **GitHub リポジトリを public にする時期**：台帳の OI-06
- **横断の仕組みを業務機能の残りより先に入れる順**：M15〜M20 の分だけ、取消・検収・請求の実装が後ろへずれる。業務機能を先に通したいなら、M19（監査ログ）と M20（スキーマの差分検査）だけを先にし、残りを M26 の後へ回す案がある
- **監査ログの保存期間**：7 年で仮に置いた（`architecture/data-model.md`「監査ログ（`platform`）」）
- **SLO の値**：`implementation-plan.md` M31 の値は初めの目安で、実測の後に見直す
- **発注側に単価の改定の予定を見せるか**：いまは今日の単価だけを見せる。見せるなら、経路 1 の型にフィールドが増える（`adr/006` 決定 7）
- **取り込みで失敗した行があるときの扱い**：行ごとに独立に反映し、失敗した行だけを報告する（`implementation-plan.md` M29 の判断）。全部か無しかを求めるなら、方式を変える

## 次にやること

再開する人は、`guides/dev-cycle.md` の流れに沿って、`implementation-plan.md` のマイルストーンを実装する。サイクルの区切りは `dev-cycle.md`「全体の流れ」の表にあり、サイクル 01（M15〜M20）・サイクル 02（M34・M35・M21〜M24）・サイクル 03（M36・M25・M26・M28・M27・M29）はサイクル末まで終えた（`plans/cycle-01/`〜`plans/cycle-03/`）。サイクル 04（M37・M30・M31・M32・M33）は計画レビューを終えた（`plans/cycle-04/plan-review.md`）。M37・M30・M31・M33 は Go、M32 は名指しされた完了条件を直して Go である。M37・M30 は実装し、実装レビューを `plans/cycle-04/implementation-reviews.md` の各節に書いた。次は M31 の実装で、ブランチは M30 の PR がマージ済みなら main から、マージ前なら `m30-metrics` から切る。業務の今日の時刻帯（OI-117）・操作者のいない入口の公開 API の規則（OI-118）・`correctItemPrice` の理由の上限（OI-120）は作者が決め、M32 の作るものに入れた。作者の判断を待つ行は、M33 の着手を止めるもの（著者判断 OI-07〜OI-14）と終えるのを止めるもの（OI-06）だけで、M31・M32 は作者を待たずに進められる。M33（フロントエンド）は、流用元の `factory-ops-demo` の刷新後の画面部品を前提に計画を済ませてあり、作者の方針で最後に実装する。

残件は、この文書には書かず、台帳 `plans/open-items.md` だけに書く。マイルストーンに着手する前に、引当先がそのマイルストーンの行を台帳で読む。M33 の著者判断（OI-07〜OI-14）は、M33 に着手する前に作者に確かめる。

決めたことを書く置き場は、`dev-cycle.md`「文書の置き場と、書く前の振り分け」にある。

### 1 つのマイルストーンの回し方

`guides/dev-cycle.md`「2. マイルストーンの実装」にある。ブランチと PR の積み重ね方、テストから書く手順、完了の判定、実装レビューの観点を決めている。

### 開発環境

- `export PATH="$HOME/.rbenv/shims:/opt/homebrew/opt/libpq/bin:$PATH"`（Ruby 3.4.11、pg_dump 18。この版にする理由は `Dockerfile` の `RUBY_VERSION` の直前のコメントにある）
- DB は `docker compose up -d --wait`（PostgreSQL 18、ポート 5433）
- rspec の全件は手元で約 1 分 10 秒かかる。テストを並行して流すときは、別名の一時 DB を使う
- GitHub の操作（push・PR）は、`GH_TOKEN=$(gh auth token -u ringoshogo)` を付けて個人アカウントで行う。gh の既定は仕事用の `ringo-shg` で、そのままでは push できない。`gh auth switch` は gh の既定のアカウントを変えてしまうので使わない

## リポジトリの状態

- **このリポジトリ**：リモートは GitHub の `ringoshogo/factory-ops-demo-rails`（private）。git の作者も ringoshogo にする。
- **ブランチ**：M1〜M20、サイクル 01 のサイクル末（#30）、サイクル 02 の計画レビューと M34・M35・M21〜M24（#31〜#38）、サイクル 02 のサイクル末（#39）、サイクル 03 の計画レビュー（#40）、M36・M25・M26・M28・M27・M29（#42〜#47）、サイクル 03 のサイクル末（#48）は main にマージ済み。サイクル 04 の計画レビュー（`cycle-04-plan`）と M37（`m37-scope-matrix`）と M30（`m30-metrics`）は、それぞれ base を main にした PR にある。Dependabot の依存更新の PR が 2 本（#15・#16）、未処理で残っている。
- **実装**：サイクル 02 のマイルストーンをすべて実装し、サイクル末を終えた。サイクル末で、監査の行を比べる example・ロックを取るメソッドの競合テスト・S1 の一覧の対照を確かめる検査と、テストの環境で bootsnap の命令列のキャッシュを止める設定を足した（`plans/cycle-02/recurrence.md`）。受注側は取引先と締め日を指定して締め、締め日以前に検収された未請求明細を集めた下書きの請求書を作り、破棄できる。締めは請求条件の行ロックで取引先ごとに直列になり、税は請求書・税率ごとに 1 回だけ切り捨てる（`architecture/data-model.md`「請求（`billing`）」）。実装レビューは `plans/cycle-02/implementation-reviews.md`「M24 請求の締め」にある。M36 で、行列テストの世界をファイルごとに 1 回作る形にし、競合テストの後始末のガードと、request spec の補助（`spec/support/request_helpers.rb`）と、上限ちょうどの example を足した。業務の振る舞いは変えていない。全件は 534 秒から約 71 秒に、CI の test のジョブは約 12 分から約 2 分半になった。実装レビューは `plans/cycle-03/implementation-reviews.md`「M36」にある。M25 で、受注側は下書きの請求書を確定して請求番号を振り、発注側は「請求書発行」の写しを受領請求書として読む。確定は締めと破棄と同じ請求条件の行ロックで直列になり、確定した請求書と結んだ集計・明細の書き換えは DB のトリガーが拒む（`architecture/data-model.md`「請求（`billing`）」）。取消・検収・請求の操作は `admin` に限り、行列テストは mutation の行ごとに許す役割を確かめる。実装レビューは `plans/cycle-03/implementation-reviews.md`「M25」にある。M26 で、受注側は受注の状況ごとの件数・安全在庫を下回る在庫・期限の近い出荷依頼・未請求の合計を `supplier.dashboard` の 1 つの問い合わせで読む。今日は日本時間で決める（`architecture/graphql-schema.md`「読み取りの一覧」）。出荷依頼がまだ無い受注への「出荷停止」と「出荷可能」の受け手は、受注 ID ごとのアドバイザリロックで直列になる（`architecture/data-model.md`「出荷（`fulfillment`）」）。重要シナリオ S2（失効の通し試験）と、画面の問い合わせの複雑度のテストを足した。実装レビューは `plans/cycle-03/implementation-reviews.md`「M26」にある。M28 で、購買の「請求書発行」の受け手が、受領請求書と同じトランザクションで発注側の `admin` への確実なメールの送信を登録し、受注の確定が受注側の `admin` への撃ちっぱなしのメールを登録する。外部へ作用するジョブは `Notifications::Email` の 1 つの登録口からだけ登録され、カスタム Cop と呼び出し元の spec がそれを守る。SendGrid の配信結果は署名付きの Webhook で受け、受信の表に書いてから処理する。テストはメモリ、開発は `tmp/mails/` に送り、WebMock が外部への HTTP を止める（`adr/007`、`architecture/data-model.md`「通知（`notifications`）」）。ワーカーはキューごとに 4 つに分けた（`guides/config.md`「ジョブ」）。実装レビューは `plans/cycle-03/implementation-reviews.md`「M28」にある。M27 で、販売単価を `item_prices` に有効期間と記録期間の 2 軸で持ち、`items.unit_price` を消した。受注側の `admin` は改定を前もって予約し（`scheduleItemPrice`）、入力の誤りを過去の行を書き換えずに訂正する（`correctItemPrice`）。カタログは今日の単価を返し、受注明細は受注日の単価とその有効日を写し、請求対象明細は発行の時点の単価といまの単価を `priceExplanation` で返す。行の書き換えと記録期間の重なりは DB のトリガーと排他制約が拒む（`adr/006`、`architecture/data-model.md`「受注（`sales`）」）。既存の DB は rake タスク `sales:backfill_item_prices` で写す。実装レビューは `plans/cycle-03/implementation-reviews.md`「M27」にある。M29 で、受注側は品目と単価・在庫の CSV（50,000 行まで、10 MB まで）を `POST /imports/files` で置き、`startImport` で取り込む。品目の CSV は `admin` に限る。取り込みのジョブ `Imports::RunJob` は、置き場へ写す・反映する・締めるの 3 段階をチャンクごとのトランザクションで進め、専用の `imports` のキューで動く。止めても、継続の情報を失っても続きから進み、同じ取り込みの 2 つのジョブでも結果は 1 つになる。既存の品目の単価の列は、改定の予約（`Sales::ItemPrices.schedule`）でだけ反映する（`adr/007` 決定 5 の A-4、`architecture/data-model.md`「取り込み（`imports`）」）。進み具合と失敗した行は `supplier.import` で読み、ジョブを失った取り込みは rake タスク `imports:reenqueue` で登録し直す。実装レビューは `plans/cycle-03/implementation-reviews.md`「M29」にある。サイクル 03 のサイクル末で、ロックを取る DB の関数にも競合テストを求める表、コメントの台帳の ID を止める Cop、CI の検査と完了条件の一覧を照らす spec、表の行列の `RETURNING` の無い INSERT を足し、受信の表の説明を直した（`plans/cycle-03/recurrence.md`・`conformance.md`）。rspec は 2307 examples, 0 failures（`cycle-03-end` で、Ruby 3.4.11 で `COVERAGE=1 bundle exec rspec`）。サイクル 04 の計画レビューで、M37・M30〜M33 の節を直した（`plans/cycle-04/plan-review.md`）。M37 で、入口の行列が、RLS の SELECT を開いて送り直した読み取りの応答を比べ、相手から読む経路の無い表の公開 API の scope の抜けを捕まえるようにした。ポリシーはテストの DB にだけ、行列の spec の補助が世界の前後で足し外しする（`guides/testing.md`「行列テストとの分担」）。読み取りの行にも許す役割を持たせ、全ペルソナの `member` で呼ぶ（`architecture/graphql-schema.md`「役割による制限」）。業務の振る舞いは変えていない。実装レビューは `plans/cycle-04/implementation-reviews.md`「M37」にある。M30 で、GraphQL の操作の時間とトップレベルのエラー、ジョブの時間と待ち時間、イベントの配送の遅れ、キューの滞留、SendGrid の応答の種類、確実な通知の受け付けまでの時間、取り込みの行と時間を、Yabeda と Prometheus のメトリクスで出す。値は `Rails.event` の購読者 `Platform::MetricsSubscriber` の 1 つから作り、ラベルにテナントとユーザーを入れない。exporter は Web とワーカーに 1 つずつ立てる（`guides/config.md`「メトリクス」）。`FORBIDDEN` の出どころを `rule`・`object`・`undeclared` に分けてメトリクスで数え、mutation の戻り値を非 null にし、単価に `bigint` の最大値の上限を置いた（`architecture/graphql-schema.md`「エラー」）。実装レビューは `plans/cycle-04/implementation-reviews.md`「M30」にある。rspec は 2526 examples, 0 failures（`m30-metrics` で、Ruby 3.4.11 で `bin/ci`）。次は M31 の実装。`implementation-plan.md` のマイルストーンを終えるたびに、ここへ書く。
- **親のモノレポ（`shogo-project`）**：`.gitignore` に `/factory-ops-demo-rails/` を追加し、README の「別リポジトリで管理しているもの」の表に行を足した。どちらも未 commit である。

## 持ち込まなかったもの

`decisions.md` は、作者の勤務先で行った 3 者の討論（Rails Way 派・構造化派・Codex）の結論である。討論の原文と、根拠として添えていた勤務先コードの観察は、社内のコードを含むため持ち込んでいない。勤務先のコード・社名・顧客名は、このリポジトリに書かない。
