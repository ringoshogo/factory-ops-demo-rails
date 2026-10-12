# サイクル 04 の知見の収穫

サイクル 04（M37・M30・M31・M32）の実装で分かったことのうち、正本に無いものを正本へ書いた記録である。手順は `guides/cycle-end.md`「2. 知見の収穫」にある。逸脱検査（`conformance.md`）は、ここで足した正本を含めて成果物と突き合わせる。再発防止（`recurrence.md`）は、ここにある知見を 2 度書かない。

読んだものは、サイクルの diff（`git diff c06cd1f..d6adfa0`）、振り返りの想定外（`retrospective.md`）、台帳の `judgment` の行（OI-122〜OI-141）と改善の候補（IB-50〜IB-63）、実装レビューの証跡の「実装の記録」、正本（`architecture/`・`adr/`・`guides/`・`README.md`「開発環境」）と `showcase.md` である。diff の層ごとの読み取りは、取りまとめ役とも実装者とも別の Claude のサブエージェントに `d6adfa0` の版で頼み、結果をファイルと行で確かめてから書いた。`lib/` が packwerk の検査に掛かることは、`lib/` に他のパッケージの非公開の定数を参照するファイルを一時に置き、`bin/packwerk check` が 1 件を出すことで確かめた。マイルストーンの中で正本に書き足した分（`config.md`「メトリクス」「メンテナンスの切り替え」、`graphql-schema.md`「エラー」と操作者のいない入口の規則と「監査ログ」、`data-model.md` の在庫と取り込みの後始末と `tenants` の入口、`testing.md`「行列テストとの分担」、`adr/005` 決定 6、`README.md`「開発環境」、`slo.md`、`runbooks/`）は済んでいるので、ここではその漏れを拾った。

## 正本に書いた項目

| 層 | 項目 | 分類 | 正本の状態 | 書いた文書と節・内容 | 根拠 |
|---|---|---|---|---|---|
| 公開 API | 日本時間の今日で決まる業務の日付は、操作の日で決まるもの（受注日・発注日・検収日・請求書の発行日・単価の有効日、単価の改定日の下限、取り込みで改定日を省いたときの改定日）で、出荷日・希望納期・出荷指示の予定日・締め日は利用者が入力で渡す | 満たすこと | 不正確。今日で決まる日付に「出荷日」と「締めと取り込みの今日」を挙げていた。出荷日は `postShipment` の入力、締めは締め日を入力に取る | `architecture/context-map.md`「検収と請求の流れ」 | `b5ed10b`・`47a6036` |
| テスト | 業務の日付を今日で決める公開 API を足す人は、日本時間の 0〜9 時の境目の example を単体に置く | 作り方 | 無い。M32 で同じ形の example を 7 つのファイルに足したが、規則が無い | `guides/testing.md`「層への配分」 | `47a6036` |
| テスト | `spec/scenarios` にはシードと E2E の世界の spec（`demo_world_spec.rb`・`seeds_spec.rb`）も置き、`--tag scenario` で流れる | 作り方 | 不正確。シナリオの層は「重要シナリオと競合テスト」だけと書いていた | `guides/testing.md`「テストの層」の表、「重要シナリオ」の `:scenario` の段落 | `2ca7521` |
| テスト | イベントの受け手と状況の値を足す人は、`DemoWorld` の世界も合わせる。合わせないと `receivers_spec.rb` と `demo_world_spec.rb` が落ちる | 作り方 | 無い。2 つの spec が世界を対照にしていることが、文書のどこにも無い | `guides/testing.md`「重要シナリオ」 | `2ca7521`・`baec471` |
| CI と設定 | 直下の `lib/`（`DemoWorld`・カスタム Cop）もルートパッケージに属し、packwerk がほかのパッケージの非公開の定数への参照を落とす | 作り方 | 無い。直下の `app/` だけを書いていた | `guides/packs-and-packwerk.md`「packs/ に並ぶもの」 | `2ca7521` |
| CI と設定 | `bin/rubocop` が `Rails/Date`・`Rails/TimeZone` を有効にしている | 手順 | 不正確。カスタム Cop だけを挙げていた | `guides/bin.md`「コミットの前に流す検査」 | `47a6036` |
| CI と設定 | `bin/setup --reset` の `db:reset` はシードも流す。シードを流す間は `bin/jobs` を止める | 手順 | 不正確。`db:reset` を流すとだけ書き、`bin/jobs` を起こす節にシードとの関係が無かった | `guides/bin.md`「手元で最初に使う」の表、「bin/dev がジョブを処理しないこと」 | `2ca7521`・`baec471` |
| CI と設定 | 本番のコンテナで、Web とワーカーに `METRICS_PROCESS` と `PROMETHEUS_EXPORTER_PORT` を渡し、Web に `WEB_CONCURRENCY` を設定しない | 手順 | 無い。`config.md`「exporter と値の置き場」にだけあり、コンテナの起動を書いた節に無かった | `guides/bin.md`「本番のコンテナが使うもの」。理由は `config.md` を参照させた | `a7df5eb`・`215448e` |
| CI と設定 | シードで今日から決める日付は、希望納期・出荷日・出荷指示の予定日・単価の改定日・締め日（月末） | 手順 | 不正確。出荷指示の予定日と締め日が無かった | `README.md`「開発環境」 | `2ca7521` |
| CI と設定 | `docs/slo.md` と `docs/runbooks/` | 手順 | 無い。文書の一覧に M31 で足した 2 つが無かった | `README.md`「ドキュメント」 | `a5888fe` |
| CI と設定 | 見せどころの実装の状態（受領請求書・取消と出荷の競合テスト・販売単価の履歴・メトリクスと SLO） | 手順 | 不正確。M22・M25・M27・M30・M31 で実装したものを「計画」と書いていた | `showcase.md` のテーマ 3・4・7・10 の「状態」と「どう確かめられるか」 | `a7df5eb`・`a5888fe`・`b670684` |

## 書かなかった項目

| 層 | 項目 | 理由 |
|---|---|---|
| 表とマイグレーション | サイクル 04 に表とマイグレーションの変更は無い | — |
| 公開 API | 置いたままのファイルの後始末と、後始末と開始のロック（OI-122・OI-137） | 正本にある（`data-model.md`「取り込み（`imports`）」、`graphql-schema.md`「mutation の一覧」の `startImport`） |
| 公開 API | 操作者のいない入口の 3 つの規則と例外、受け手と公開 API に足した所有の条件 | 正本にある（`graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」）。個々の書き方は実装の手段 |
| 公開 API | `Onboarding.register`・`Stocks.set_safety_stock` の形、送信の公開 API の戻り値（OI-125・OI-140） | 正本にある（`data-model.md`「RLS」「在庫（`inventory`）」、`graphql-schema.md` の操作者のいない入口の規則） |
| 公開 API | `require_tenant!` と `default_scope` が重なる、SELECT を開いても見えない所有の条件 | 改善の候補 IB-59・IB-60 にある。確かめられないことは `testing.md`「行列テストとの分担」にある |
| 公開 API | 理由の上限・単価の上限、販売単価の記録期間の型 | 正本にある（`graphql-schema.md`「mutation の一覧」、`config.md`「application.rb で変えたこと」） |
| 公開 API | ユーザーエラーの文の言語、定期のジョブの 1 社の例外 | 改善の候補 IB-63・IB-57 にある |
| GraphQL | `FORBIDDEN` の出どころ、mutation の戻り値の非 null、例外の経路のイベント、メンテナンスの切り替え（OI-124・OI-126・OI-129・OI-130・OI-135） | 正本にある（`graphql-schema.md`「エラー」、`config.md`「イベントごとに書く項目」「メンテナンスの切り替え」） |
| GraphQL | API の時刻の表記（`ISO8601DateTime` は `+09:00` 付き） | 正本にある（`config.md`「application.rb で変えたこと」）。`graphql-schema.md` にはスカラーを扱う節が無く、M33 の計画が画面でのスカラーの写し方を決めているので、置き場は M33 で画面の問い合わせを書くときに決める |
| ジョブとイベント | `DemoWorld::Jobs` の流し方と後始末、claim しないこと、途中で失敗した世界 | 正本にある（`adr/005` 決定 6、`testing.md`「重要シナリオ」、`README.md`「開発環境」）。残りは IB-61・IB-62 |
| ジョブとイベント | シードが監査の行を書かない（OI-141） | 正本にある（`graphql-schema.md`「監査ログ」） |
| ジョブとイベント | 待ち時間を付けて登録し直したジョブの滞留、トランザクションの中で出すイベント | 台帳にある（OI-131、IB-51） |
| テスト | 入口の行列の 2 回目、ポリシーの足し外し、入れ子のフィールドの公開 API、共有の文脈「RLS の SELECT を開く」 | 正本にある（`testing.md`「行列テストとの分担」）。判断は OI-127・OI-128、残りは IB-50・IB-52 |
| テスト | ロックを取るメソッドの表に後始末と開始を足した、複数プロセスの値の集計 | 実装の手段（表の規則は `testing.md`「競合テスト」）。集計は IB-54 |
| CI と設定 | Yabeda・exporter・`DirectFileStore`・`webrick`・メトリクスとラベル・バケット | 正本にある（`config.md`「メトリクス」）。判断は OI-133、残りは IB-53 |
| CI と設定 | `config.time_zone`・DB の時刻は UTC・SQL で今日を取らない | 正本にある（`config.md`「application.rb で変えたこと」） |
| CI と設定 | `bin/check-alerts`・`recurring.yml` の後始末のジョブ | 正本にある（`bin.md`、`config.md`「CI の工程」「ジョブ」、`slo.md`） |
| 運用の文書 | SLO の値・倍率・警報の式・`le` の表記・手順書のコマンド（OI-134・OI-136） | 正本にある（`slo.md`・`runbooks/`）。残りは IB-55・IB-56・IB-58 |
| シード | 世界の中身と形（OI-123・OI-138・OI-139） | 正本にある（`README.md`「開発環境」） |
| CI と設定 | 空の DB で `bin/setup`（`db:prepare`）がシードまで流すか | 確信を持てない。activerecord 8.1.4 は作った DB の設定がシードを持つときだけ流すが、開発の `db:prepare` で回る所有ロールの設定が当たるかを確かめていない。次のサイクルで、空の DB で流して確かめる |
| CI と設定 | `DemoWorld` が本番でも読み込まれること（`autoload_lib`） | 確信を持てない。本番では `build` が例外で止まり、読み込むだけでは害が無い。読み込みから外すかは判断が要るので、次のサイクルへ送る |

## 見た層

| 層 | 見たもの | 書いた項目 |
|---|---|---|
| 表とマイグレーション | `db/migrate`・`structure.sql` に diff が無いこと、`db/seeds.rb`・`db/seeds/demo_accounts.json` | 無し |
| 公開 API | 取り込み・在庫・通知・取引関係・受注・出荷・購買・請求の公開 API と受け手の diff、`Date.current` の呼び出し元 | 業務の日付 |
| policy | `lib/demo_world/operations.rb`。policy のファイルの diff は無い | 無し |
| GraphQL | 2 つのコントローラとメンテナンスの切り替え、宣言と `ForbiddenError`、mutation の基底クラス、ダッシュボード、`postShipment` | 無し |
| ジョブとイベント | 後始末のジョブ、通知のジョブと SendGrid、`DemoWorld` と `DemoWorld::Jobs`、メトリクスの購読者、`imports.rake` | 無し |
| テスト | spec の diff を見出しと時刻帯で走査し、`receivers_spec.rb`・`time_zone_cops_spec.rb`・`demo_world_spec.rb`・`seeds_spec.rb`・`logging_spec.rb`・`config/test_layers.yml` を読んだ | 時刻帯の境目、シナリオの層、世界を合わせること |
| CI と設定 | ワークフロー・`.rubocop.yml`・Gemfile・`bin/check-alerts`・`bin/setup`・`application.rb`・`ci.rb`・`graphql_operations.yml`・メトリクスの初期化・警報の規則・`puma.rb`・`recurring.yml`・`packwerk.yml`・`Dockerfile` | `lib/` のパッケージ、Cop の一覧、`bin/setup` と `bin/jobs`、本番の環境変数、シードの日付、文書の一覧、見せどころの状態 |
| 運用の文書 | `slo.md`、`runbooks/` の 5 本 | 無し |
