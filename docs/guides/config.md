# config/ の設定ファイル

`config/` には、Rails が起動するときに読む設定と、DB・ジョブ・CI などの道具が読む設定が並ぶ。多くは `rails new` が生成したままで、本デモが手を入れたのは一部である。この文書は、まず全ファイルの一覧で生成のままか変えたかを示し、次に変えたものを目的ごとに、何を変えたかとその理由を説明する。

## 一覧

「出自」の「生成のまま」は `rails new` が作った内容から変えていないもの、「変更」は生成されたファイルに手を入れたもの、「追加」は本デモで足したファイルである。

| ファイル | 役割 | 出自 | 説明する節 |
|---|---|---|---|
| `boot.rb` | Bundler と bootsnap を読み込む。起動の最初に読まれる | 変更 | [boot.rb で変えたこと](#bootrb-で変えたこと) |
| `application.rb` | アプリ全体の設定 | 変更 | [起動とリクエスト](#起動とリクエスト)・[DB の接続](#db-の接続)・[ジョブ](#ジョブ)・[ログ](#ログ) |
| `environment.rb` | `application.rb` を読み込み、アプリを初期化する | 生成のまま | — |
| `environments/development.rb`・`test.rb`・`production.rb` | 環境ごとの設定 | 変更 | [環境ごとの設定](#環境ごとの設定)・[ログ](#ログ) |
| `initializers/cors.rb` | CORS の設定。全行がコメント | 生成のまま | [起動とリクエスト](#起動とリクエスト) |
| `initializers/event_log.rb` | `Rails.event` のイベントを 1 行の JSON で書く購読者を登録する | 追加 | [ログ](#ログ) |
| `initializers/filter_parameter_logging.rb` | ログに出さないパラメータ | 生成のまま | [ログ](#ログ) |
| `initializers/notifications.rb` | 起動時に通知の送信先を作り、本番以外で SendGrid の sandbox mode を外した設定を止める | 追加 | [ジョブ](#ジョブ) |
| `initializers/metrics.rb` | メトリクスを定義し、`Rails.event` のイベントから値を作る購読者を登録する | 追加 | [メトリクス](#メトリクス) |
| `initializers/inflections.rb` | 単数形・複数形の規則。全行がコメント | 生成のまま | — |
| `initializers/strong_migrations.rb` | 危険なマイグレーションを止める gem の設定 | 追加 | [DB の接続](#db-の接続) |
| `initializers/tenancy.rb` | 接続を貸し出すたびにテナントの設定を空にする | 追加 | [DB の接続](#db-の接続) |
| `routes.rb` | URL とコントローラの対応 | 変更 | [起動とリクエスト](#起動とリクエスト) |
| `puma.rb` | Web サーバー Puma の設定。起動の後にメトリクスの exporter を立てる | 変更 | [メトリクス](#メトリクス) |
| `graphql_operations.yml` | メトリクスのラベルに使ってよい GraphQL の操作名 | 追加 | [メトリクス](#メトリクス) |
| `prometheus/alerts.yml`・`alerts_test.yml` | Prometheus の警報の規則と、そのテスト。`bin/check-alerts` が promtool で流す | 追加 | [../slo.md](../slo.md) |
| `database.yml` | DB の接続先とロール | 変更 | [DB の接続](#db-の接続) |
| `queue.yml` | Solid Queue のワーカーの設定 | 追加（生成器の後に変更） | [ジョブ](#ジョブ) |
| `recurring.yml` | Solid Queue の定期実行 | 追加（生成器の後に変更） | [ジョブ](#ジョブ) |
| `test_layers.yml` | テストの層ごとの置き場と、割合の目安。`bin/test-layers` が読む | 追加 | [testing.md「テストの層」](testing.md#テストの層) |
| `branch_coverage.yml` | 分岐の網羅率の計測の対象。`spec/support/branch_coverage.rb` と `bin/check-branch-coverage` が読む | 追加 | [testing.md「分岐の網羅率の警告」](testing.md#分岐の網羅率の警告) |
| `ci.rb` | `bin/ci` が流す工程 | 変更 | [CI の工程](#ci-の工程) |
| `bundler-audit.yml` | `bin/bundler-audit` が無視する CVE | 生成のまま | — |
| `credentials.yml.enc` | 暗号化した秘密情報 | 生成のまま | [使っていない機能の設定](#使っていない機能の設定) |
| `locales/en.yml` | 翻訳の見本 | 生成のまま | [使っていない機能の設定](#使っていない機能の設定) |

Rails は、`bin/rails server` などで起動するとき、`boot.rb` → `application.rb` → `environment.rb` の順に読み、初期化の中で `environments/<環境>.rb`、`initializers/*.rb`、`routes.rb` を読む。

## 起動とリクエスト

### boot.rb で変えたこと

テストの環境（`RAILS_ENV=test`）では、bootsnap の命令列のキャッシュを使わない（`DISABLE_BOOTSNAP_COMPILE_CACHE`）。bootsnap は、ファイルの大きさと更新時刻（秒）が前と同じなら、キャッシュした命令列を返す。実装を壊して落ちることを確かめる手順（`guides/dev-cycle.md`「テストから書く」）では、比較の演算子を入れ替えるような大きさの変わらない壊し方をし、同じ秒のうちに複製から戻すことがあり、そのとき戻した後も壊した版が読まれる。`spec/platform/compile_cache_spec.rb` が、同じ秒に同じ大きさで書き換えたファイルを、書き換えた後の中身で読むことを確かめる。読み込みの道のキャッシュ（`load_path_cache`）は、ファイルの中身を持たないので使い続ける。開発と本番の起動は変えない。

### application.rb で変えたこと

`application.rb` は `config.api_only = true` の API モードで、生成のままの部分から使わない部品の読み込みを外し、次の 8 つを足した。DB・ジョブ・ログに関わる 4 つは、それぞれの節で説明する。外した部品は [使っていない機能の設定](#使っていない機能の設定) で説明する。

- **`autoload_lib` の除外に `rubocop` と `schema_compat.rb` を足す。** `lib/rubocop/` はカスタム Cop で、`lib/schema_compat.rb` はスキーマの互換の判定である。どちらも開発とテストのグループにしかない gem（rubocop・graphql-schema_comparator）を読むので、本番の起動では読めない。自動読み込みの対象から外す。
- **Cookie とセッションのミドルウェアを足す。** API モードの Rails は、Cookie とセッションのミドルウェアを持たない。本デモはログインを Cookie のセッションで保つので、`ActionDispatch::Cookies` とセッションのストアを明示的に足す。セッションの Cookie は `SameSite=Lax` にし、本番では `secure` を付け、最後のリクエストから 12 時間で切れるようにする（[graphql-schema.md「1 回のリクエストがたどる道」](../architecture/graphql-schema.md#1-回のリクエストがたどる道) 1）。
- **`config.time_zone = "Asia/Tokyo"` にする。** 業務の今日（受注日・発注日・検収日・請求書の発行日・単価の有効日・取り込みの改定日・ダッシュボードの今日）は、どれも `Date.current` で決まるので、使う会社のある日本時間にする（[context-map.md「検収と請求の流れ」](../architecture/context-map.md#検収と請求の流れ)）。UTC のままだと、日本時間の 0〜9 時の操作が前日の日付になる。DB に書く時刻は `ActiveRecord.default_timezone` の既定の UTC のままで、DB のセッションの時刻帯も UTC のままにするので、既存の行は書き換えない。GraphQL の `ISO8601DateTime` とイベントのペイロードと付帯情報の時刻は、`Z` ではなく日本時間のオフセット（`+09:00`）付きで書かれる。指す時点は変わらない。そのため、SQL で今日を取らない（`CURRENT_DATE`・`now()::date` はセッションの UTC の日付になる）。システムの時刻帯で決まる `Date.today`・`Time.now`・`Time.parse` は、`.rubocop.yml` で有効にした `Rails/Date`・`Rails/TimeZone` の Cop が落とす。アプリの時刻帯が UTC でないと、activerecord 8.1 は始まりが時刻の終わりの無い範囲の終わりを `infinity` で書くので、販売単価の記録期間（`tstzrange`）は、終わりを空で書く型（`Sales::RecordedPeriodType`）で持つ
- **`schema_format = :sql`**（[DB の接続](#db-の接続)）
- **`queue_adapter = :solid_queue`**（[ジョブ](#ジョブ)）
- **`config.x.notifications.from`**：通知のメールの差出人（[ジョブ](#ジョブ)）
- **`config.x.frontend_origin`**：フロントエンドのオリジン。環境変数 `FRONTEND_ORIGIN` で渡し、無ければ開発の `http://localhost:3001` にする（[CSRF を防ぐ前提：CORS を開けない](#csrf-を防ぐ前提cors-を開けない)）
- **`Platform::RequestContext` のミドルウェア**（[ログ](#ログ)）

### CSRF を防ぐ前提：CORS を開けない

API モードは CSRF 対策（フォームのトークン）を持たない。本デモは、次の 3 つの組み合わせで他サイトからの書き込みを防ぐ。

1. セッションの Cookie を `SameSite=Lax` にし、他サイトからの POST に Cookie を付けさせない（`application.rb`）。
2. `ApplicationController` が、本文が `application/json` でないリクエストを 415 で拒む。他サイトのフォームは `application/json` を送れない。
3. CORS を開けない。`initializers/cors.rb` は生成のまま全行がコメントで、`rack-cors` も Gemfile でコメントのままである。他サイトの JavaScript が `fetch` で `application/json` を送るには CORS のプリフライトが要り、それが通らない。

画面（`frontend/`）は、ブラウザから見えるオリジンを Next の 1 つだけにする。ブラウザは Next のサーバーだけを呼び、Next のサーバー（サーバーコンポーネントと server action）が Rails へ `application/json` で送る。ブラウザからの書き込みは server action を通り、Next が `Origin` と `Host` の一致を確かめる。Rails のセッションの Cookie は、Next がフロントエンドのオリジンの Cookie として同じ属性で写す（`frontend/lib/session.ts`）。

例外は、取り込むファイルの受け口（`POST /imports/files`、`ImportFilesController`）である。ブラウザが `multipart/form-data` で CSV を直接送るので、2 の `application/json` の制限を外す。代わりに、`Origin` ヘッダが `config.x.frontend_origin` と一致しない要求と、`Origin` の無い要求を 403 で拒む。ブラウザは別のオリジンからの POST に必ず `Origin` を付けるので、他サイトのフォームからの送信はここで止まる。画面は、ブラウザから同じオリジンの `/imports/files` へ送らせ、Next の route handler（`frontend/app/imports/files/route.ts`）が本文とブラウザの `Origin` をそのまま Rails へ送る。他サイトのフォームからの送信は、Next を通っても他サイトの `Origin` を運ぶので、ここで止まる。本番では `FRONTEND_ORIGIN` にフロントエンドのオリジンを渡す。渡さなければ開発の値のままになり、本番のブラウザからの送信はすべて拒まれる。

フロントエンドを別のオリジンから呼ぶことになったら、`cors.rb` を有効にする前に、この前提を見直す。

### routes.rb で足したもの

生成のままの `GET /up`（死活監視）に、次の 4 つを足した。

- `resource :session, only: %i[create destroy]`：ログインとログアウト（`SessionsController`）。GraphQL に認証の mutation は置かない
- `post "graphql"`：GraphQL の入口（`GraphqlController`）。POST だけを受け付ける
- `post "imports/files"`：取り込むファイルの受け口（`ImportFilesController`）。セッションで認証し、`Origin` で CSRF を防ぐ。10 MB を超えるファイルは読む前に 413 で拒む。ファイルを置くだけで、取り込みは `startImport` で始める
- `post "webhooks/sendgrid/events"`：SendGrid のイベント Webhook の受け口（`Webhooks::SendgridEventsController`）。セッションを読まず、署名で認証する（[ADR 007](../adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md) 決定 5 の A-3）

### メンテナンスの切り替え

運用者は、テナントの境界の不具合が疑われる間（[runbooks/rls-misconfiguration.md](../runbooks/rls-misconfiguration.md)）、Web のプロセスに環境変数 `MAINTENANCE_MODE` を設定して起動し直し、業務の表を読み書きする入口を止める。`GraphqlController` と `ImportFilesController` は `MaintenanceMode`（`app/controllers/concerns/`）を取り込み、立っていれば何も実行せずに 503 を返す。本文の形の検査とセッションの確かめより先に止めるので、どの要求も同じ 503 になる。

| 入口 | 立てたとき | 理由 |
|---|---|---|
| `POST /graphql`・`POST /imports/files` | 503 | 業務の表を読み書きする |
| `POST /session`・`DELETE /session` | 止めない | ログインはメールアドレスでユーザーを引く認証の関数だけを通り、ログアウトは自分のセッションの世代を進める（`SHARED_DEMO_ACCOUNTS=1` では進めない）だけで、業務の表を読み書きしない。ログアウトを止めると、利用者が漏れたセッションを無効にできない |
| `POST /webhooks/sendgrid/events` | 止めない | 受信の表に書くだけで、止めると配信結果を失う |
| `GET /up` | 止めない | 死活監視が、止めた Web をプロセスの障害と取り違えて起動し直す |

値は Rails の真偽値の読み方（`ActiveModel::Type::Boolean`）で読み、空の文字列と、`0`・`f`・`false`・`off`（大文字を含む）は立てない側に、それ以外の値は立てる側に倒す。環境変数はプロセスの起動の時に決まるので、切り替えはプロセスの再起動で効く。ワーカー（`bin/jobs`）は切り替えで止まらないので、止めるなら別に止める。`spec/requests/maintenance_mode_spec.rb` が、立てたときに GraphQL とファイルの受け口が 503 で何も書かず、ログインと Webhook が通り、立てないときに同じ要求が書くことを確かめる。

## DB の接続

### database.yml：同じ DB に 2 つのロールで接続する

生成のままの `database.yml` は、環境ごとに接続先を 1 つ置く。本デモは、同じ DB に `primary` と `owner` の 2 つの設定を置く（[data-model.md「RLS」](../architecture/data-model.md#rls)）。

| 設定 | 接続するロール | 使う人 | 鍵になる項目 |
|---|---|---|---|
| `primary` | `factory_app`（アプリのロール。一般ロール） | アプリ・テスト・ワーカー | `database_tasks: false`（DB のタスクの対象から外す） |
| `owner` | `factory_owner`（所有ロール。表の所有者で `BYPASSRLS`） | DB のタスク（作成・マイグレーション・スキーマの読み込み） | `migrations_paths: db/migrate`、`schema_dump: structure.sql` |

ロールを分けるのは、表の所有者と `BYPASSRLS` を持つロールが RLS を迂回するからである。アプリとテストが所有ロールで動くと、RLS が効いていることを確かめられない。

この構成で、開発者のコマンドは次のように振る舞う。

- `bin/rails db:migrate` などの DB のタスクは、`owner` の設定でだけ流れる。
- `db:rollback` と `db:migrate:up`・`down`・`redo` は、設定ごとに回らず `primary` の接続で流れる。`lib/tasks/db_roles.rake` が、これらを所有ロールの接続に切り替える。
- 表を作るタスクの後に、同じ rake ファイルの `db:grant_app_role` がアプリのロールへ権限を付与する。
- 本番の `owner` は、環境変数 `DB_OWNER_USER` を渡したプロセスにだけ現れる。所有ロールの資格情報を渡す工程は [data-model.md「RLS」](../architecture/data-model.md#rls) にある。

test の環境の DB の名前は、環境変数 `TEST_DATABASE` で替えられる。E2E は `factory_ops_e2e` を渡し、rspec のテスト DB と分ける。E2E の準備（`lib/tasks/e2e.rake`）は DB を作り直すので、同じ DB を使うと rspec の DB を消す。準備は、`TEST_DATABASE` が無いか rspec のテスト DB の名前なら止まる。rspec を別の DB で並べて流すときは、名前に `_test` を区切りとして含める（`factory_ops_m49_test` の形）。行列の spec（`spec/support/matrix_cross_read.rb`）は、全行を読ませるポリシーを足す前に DB の名前を見て、テストの DB と分からなければ止まるからである。

担当ごとに替える一時の DB の名前は、`factory_ops_` で始め、`_` で区切った語に `test`（rspec、`TEST_DATABASE`）か `e2e`（E2E、`E2E_DATABASE`）を含める（`factory_ops_m51_test`・`factory_ops_m51_e2e`）。一時の DB は作る入口（`bin/ci` の `db:test:prepare`、E2E の `start-rails.sh` の `db:drop db:prepare`）が作り、作った担当が止まっても残るので、`RAILS_ENV=test bin/rails temp_databases:list` で一覧し、`RAILS_ENV=test bin/rails "temp_databases:drop[<名前>]"` で消す（[bin.md「bin/rails で流す運用のタスク」](bin.md#binrails-で流す運用のタスク)）。2 つのタスクは名前の規則に合う DB だけを扱い、既定の 3 つ（`factory_ops_demo_rails_development`・`factory_ops_demo_rails_test`・`factory_ops_e2e`）は扱わない。削除は名前を明示したときだけ、所有ロールで保守用の DB（`postgres`）に接続して `DROP DATABASE` を `FORCE` なしで流すので、接続中の DB は PostgreSQL が失敗させる。動いている担当の DB を、その接続ごと切って消さないためである。test の環境でだけ動く（`lib/temp_databases.rb`）。

開発とテストの接続先は、`compose.yaml` の PostgreSQL 18（ポート 5433）である。主キーに使う `uuidv7()` は 18 から入った関数である（[ADR 003](../adr/003-主キーにUUIDv7を使う.md)）。

### 照合順序の版

名前と単位の列の照合順序 `ja-x-icu`（[data-model.md「文字列の照合順序」](../architecture/data-model.md#文字列の照合順序)）は ICU が実装し、ICU の版が上がると並びが変わりうる。PostgreSQL は、照合順序ごとに作ったときの ICU の版を `pg_collation.collversion` に記録し、イメージの ICU の版（`pg_collation_actual_version`）と違えば、その照合順序を使うたびに警告を出す。記録は DB ごとにあり、新しい DB は `template1` の記録を写す。そのため、DB を消して作り直しても、`template1` の記録が古ければ古い版のまま残る。

PostgreSQL のイメージを上げた人は、クラスタ（手元の `compose.yaml` のボリューム、公開の配置の PVC）ごとに、次の順で記録を改める。CI は毎回新しいクラスタを作るので、記録と実際の版が食い違わない。手元では、`spec/platform/collations_spec.rb` が食い違いを落とす。

1. `template1` で `ALTER COLLATION pg_catalog."ja-x-icu" REFRESH VERSION` を流す。`template1` には表が無いので、記録だけを改めてよい。手元は `PGPASSWORD=postgres psql -h localhost -p 5433 -U postgres -d template1 -c 'ALTER COLLATION pg_catalog."ja-x-icu" REFRESH VERSION'`、公開の配置は `deploy/README.md`「PostgreSQL のイメージを上げたとき」にある
2. 業務の DB を消して作り直す。作り直した DB は、`template1` の改めた記録を写し、索引を新しい ICU で作る。手元は `bin/rails db:drop db:prepare` と `bin/rails db:test:prepare`（`TEST_DATABASE` で使う DB も、それぞれの名前で）を流す。公開の配置は、作り直しを手で 1 回流す

作り直さずに残す DB で記録を改めるときは、`ja-x-icu` の列を使う索引を `REINDEX` してから `REFRESH VERSION` を流す。索引の並びは作ったときの ICU の版で決まり、記録だけを改めると、古い並びの索引を新しい並びで引いて、一意の検査と検索を誤る。

### application.rb の schema_format：structure.sql に保存する

`config.active_record.schema_format = :sql` で、スキーマを `db/schema.rb` ではなく `db/structure.sql` に保存する。マイグレーションの `execute` で作った RLS のポリシーと複合外部キーは `schema.rb` に書き出されず、`db:schema:load` で作るテストの DB に再現されない（[ADR 001](../adr/001-スキーマ管理にridgepoleを採用しない.md) 決定 1）。表の説明（`COMMENT ON TABLE`）も `structure.sql` に書き出されるので、開発者は DB に繋がずに表の説明を読める（[data-model.md「全テーブルに共通の規則」](../architecture/data-model.md#テナントの持ち方全テーブルに共通の規則)）。`structure.sql` が往復で変わらないことは `bin/check-structure` が確かめる（[bin.md](bin.md#bincheck-structure-が確かめる-2-つの往復)）。

### initializers/strong_migrations.rb：危険なマイグレーションを止める

strong_migrations は、本番で表をロックしかねない変更（列の型の変更、`CONCURRENTLY` の無い索引の追加など）を、マイグレーションの実行時に例外で止める gem である（[ADR 001](../adr/001-スキーマ管理にridgepoleを採用しない.md) 決定 3）。このファイルは生成器が作ったもので、ロックの待ち時間・文の実行時間の上限と、本番の PostgreSQL の版 `target_version = 18` を設定している。

### initializers/tenancy.rb：接続を貸し出すたびにテナントを空にする

アプリは、テナントを `Tenancy.with_tenant` の中で `SET LOCAL app.tenant_id` で DB に渡す。接続はプールで使い回すので、前の利用者が残したテナントを、テナントを設定しない次の利用者が引き継ぐことがある。このファイルは、接続プールの貸し出し（checkout）のコールバックで `Tenancy.reset!` を呼び、セッションの `app.tenant_id` を空にする（[data-model.md「RLS」](../architecture/data-model.md#rls)）。

## ジョブ

本デモは、ジョブ基盤の Solid Queue を業務 DB と同じ接続に置き、イベントのジョブを業務のトランザクションの中で登録する（[ADR 005](../adr/005-イベントのジョブをトランザクション内で登録する.md)）。設定に現れるのは次の 3 か所である。

- **`application.rb` の `queue_adapter = :solid_queue`**：全環境で同じアダプタにする。テストでも `:test` アダプタに差し替えない（ADR 005 決定 1・6）。
- **`connects_to` を書かない**：Rails 8 の既定は、`production.rb` の `config.solid_queue.connects_to` でキューを別の DB に置く。本デモはこれを書かず、`database.yml` にもキューの DB を置かない。`SolidQueue::Record` は業務と同じ接続を使うので、業務のトランザクションの中で登録したジョブは、業務データと一緒に確定するか一緒に消える。
- **`queue.yml`**：ワーカーをキューごとに分け、`events`（3 スレッド）・`external_mail`（2）・`imports`（1）・`default`（2）の 4 つにする。重い取り込みが、イベントの配送とメールを待たせないためである（[ADR 007](../adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md) 決定 7）。SendGrid への同時の送信の上限は、設定ではなく送信のジョブの `limits_concurrency` に書く。`bin/jobs` が読み、`spec/jobs/queue_config_spec.rb` が、どのジョブもワーカーのあるキューに載ることを確かめる。
- **`recurring.yml`**：開発と本番で、Webhook の受信の未処理を毎分拾うジョブと、処理を終えた行を毎日消すジョブと、置いてから 24 時間を過ぎても取り込みを始めないファイルの中身を毎時消すジョブ（`Imports::PurgeAbandonedFilesJob`。[data-model.md「取り込み（`imports`）」](../architecture/data-model.md#取り込みimports)）を流す。本番だけは、生成のままの、終わったジョブの行を毎時消すタスクも流す。

通知のメールの送信先は、環境ごとに `config.x.notifications.provider` で選ぶ。本番は SendGrid（API キーと Webhook の署名の公開鍵は credentials）で、公開の配置だけは `NOTIFICATIONS_PROVIDER=file_system` でファイルに替える（[環境ごとの設定](#環境ごとの設定)）。開発は `tmp/mails/` に 1 通 1 ファイルで書くもの、テストはメモリに積むもので、テストと開発は外部へ送らない。`initializers/notifications.rb` が起動時に送信先を作り、本番以外で SendGrid を選んで sandbox mode を外した設定を例外にする。テストは、これとは別に WebMock で外部への HTTP を止める（`spec/spec_helper.rb`）。

取り込みのジョブ（`Imports::RunJob`）は、`ApplicationJob` の `tenant_transaction :per_chunk` を宣言し、実行全体を 1 つの `Tenancy.with_tenant` で包まずに、チャンクごとにテナントのトランザクションを開いて閉じる。同時実行の上限（テナントごとに 1 つ、`duration` は 1 時間）は、ジョブのクラスの `limits_concurrency` に書く。プロセスが強制終了して失敗になった取り込みのジョブは、運用者が rake タスク `imports:reenqueue`（`IMPORT_ID` と `TENANT_ID` に失敗したジョブの引数の値を渡す）で登録し直す（[ADR 007](../adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md) 決定 5 の A-4）。

ワーカーのメトリクスの exporter は、`bin/jobs` の supervisor が worker を fork する前に 1 つだけ立てる（[メトリクス](#メトリクス)）。

公開の配置（`deploy/jobs.yaml`）では、`SOLID_QUEUE_SUPERVISOR_MODE=async` で、ワーカー・ディスパッチャ・スケジューラを 1 つのプロセスのスレッドで動かす。fork のモードの 7 つのプロセスがそれぞれ Rails を抱えると、同居する Raspberry Pi のメモリに収まらないからである（[ADR 009](../adr/009-デモを流用元と同じRaspberryPiのk3sに置き共有のデータを毎日作り直す.md) 決定 5）。キューごとのワーカーの分け方は `queue.yml` のままで、async のモードは `processes` を無視する。全ワーカーが 1 つの接続プールを分け合うので、プールの大きさ（`RAILS_MAX_THREADS`）は、`queue.yml` のワーカーごとのスレッドに、ワーカーごとのポーリングと心拍の 2 つを足した和に、ディスパッチャ・スケジューラ・スーパーバイザの分の 4 つを足した数以上にする（solid_queue 1.7.0 の README「Fork vs. async mode」）。`spec/platform/deploy_manifests_spec.rb` が `queue.yml` からこの数を計算してマニフェストの値と比べるので、ワーカーかスレッドを足した人は、マニフェストの値も直す。

ジョブを登録する時機（コミットの後か、トランザクションの中か）は設定ではなく、`ApplicationJob`（`packs/platform`）・`Contracts::EventJob`（`packs/contracts`）と、`ExternalEffectJob` のサブクラス（`packs/notifications` の送信のジョブ。書かなければ読み込みで例外になる）の `enqueue_after_transaction_commit` で決める（[ADR 007](../adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md) 決定 4）。

## ログ

本デモのログは、1 行が 1 件の JSON で、どの要求・テナント・ユーザー・GraphQL の操作・ジョブ・イベントのものかを `context` に持つ。運用者は、相関 ID（`correlation_id`）で、発注側の発注から受注側の受注確定までのように、テナントをまたぐ一連の処理を引ける。個人情報と秘密は書かない。

### ログの出口：Rails.event と Rails.logger

ログの出口は 2 つある。

- **`Rails.event`**：Rails 8.1 は、コントローラ・ジョブの計装を構造化イベント（`action_controller.request_started`・`active_job.completed` など）として `Rails.event` に出す。イベントをログに書く購読者は付属しないので、`initializers/event_log.rb` が `Platform::JsonLogSubscriber`（`packs/platform/lib/platform/`）を登録する。購読者は 1 件のイベントを `name`・`payload`・`tags`・`context`・`timestamp` の 1 行にし、本番では標準出力に、開発とテストでは `log/events.log` に書く。`TEST_DATABASE` で別の DB に向けたプロセス（E2E の Rails、並べて流す rspec）は、DB ごとのファイル（`log/events.<DB の名前>.log`）に書く。同じファイルに書くと、ログの spec（`spec/platform/logging_spec.rb`）が読む末尾にほかのプロセスの行が混ざる。ログの spec も、自分のプロセスが書くファイルを `Platform::Logging.events_log_path` で引いて読むので、`TEST_DATABASE` を渡して流す rspec は `log/events.log` を要らない。
- **`Rails.logger`**：本番とテストでは、`Platform::JsonLogFormatter` を付けたロガーにし、残る文字列の行も JSON にして、同じ文脈を `context` に入れる。ロガーは `ActiveSupport::TaggedLogging` で包まない。TaggedLogging はタグを文字列としてメッセージに混ぜてから書式に渡すので、要求 ID などはタグにせず、文脈から `context` の項目に入れる。

### イベントごとに書く項目

Rails の構造化イベントは、要求の引数・ジョブの引数・例外のメッセージを載せる。`filter_parameter_logging.rb` の `filter_parameters` は名前で値を隠すだけで、GraphQL の `query` と `variables` の中身や自由記述を覆わない。そこで購読者は、イベントの名前ごとに書く項目を次の表で決め、表に無い項目を落とす。

| イベント | 書く項目 | 書かないもの |
|---|---|---|
| `action_controller.request_started` | `controller`・`action`・`format` | `params`。`GraphqlController` の要求は、`operation_name`、`query` の SHA-256 の要約（`query_sha256`）、`variables` のキーの一覧（`variable_keys`）に置き換える。操作名と変数のキーは利用者が送る値なので、GraphQL の名前の形（`/\A[_A-Za-z][_0-9A-Za-z]*\z/`）の文字列だけを書き、ハッシュ・配列などは中の値ごと落とす |
| `action_controller.request_completed` | `controller`・`action`・`status`・`duration_ms` などの数値 | — |
| `action_controller.rescue_from_handled` | `exception_class` | 例外のメッセージとバックトレース。メッセージは DB のエラーの詳細などに入力の値を含む |
| `active_job.enqueued`・`enqueued_at`・`started`・`completed`・`retry_scheduled`・`retry_stopped`・`discarded` | `job_class`・`job_id`・`queue`・時間・`exception_class` | ジョブの引数と、例外のメッセージとバックトレース。`ApplicationJob.log_arguments = false` にし、購読者も落とす |
| `graphql.operation_completed`（アプリが出す） | `operation_name`・`operation_type`（`query`・`mutation`。文書を解析できないか、実行する操作を 1 つに決められなければ `none`）・`result`（`success`・`user_error`・`error`）・`user_error_codes`・`error_codes`（トップレベルのエラーの `extensions.code` の一覧。code の無いエラーは `none`）・`forbidden_reasons`（`FORBIDDEN` の出どころの一覧。[graphql-schema.md「エラー」](../architecture/graphql-schema.md#エラー)）・`duration_ms`。スキーマの実行が例外を上げたときも、`result` を `error` にして 1 回だけ出す | — |
| `contracts.event_handled`（アプリが出す） | `event_name`・`receiver`・`delivery_lag_ms`（受け手の始まりの時刻 − 発行時刻） | — |
| `notifications.provider_responded`（アプリが出す） | `provider`（`sendgrid`）・`status`（状態コードの百の位の `2xx`・`4xx`・`5xx` など。429 だけは `429`、接続の失敗は `timeout`）。送信 API を呼んだたびに出す | 応答の本文 |
| `notification.accepted`（アプリが出す） | `kind`・`delivery_id`・`attempts`・`acceptance_ms`（送信記録を作ってから受け付けを書くまで） | 宛先 |
| `notification.delivery_failed`（アプリが出す） | `kind`・`delivery_id`（送信記録の ID）・`reason`・`attempts` | 宛先。送信記録の ID を `email_delivery_id` と書くと、`filter_parameters` の `email` が名前の一部に当たって値が隠れる |
| `notification.best_effort_dropped`（アプリが出す） | `kind`・`reason`・`attempts` | 宛先 |
| `imports.chunk_applied`（アプリが出す） | `kind`・`import_id`・`applied_rows`・`failed_rows`（そのチャンクで新しく結果を書いた行の数） | ファイル名と行の値 |
| `imports.finished`（アプリが出す） | `kind`・`import_id`・`result`（`succeeded`・`partially_failed`・`failed`）・`total_rows`・`applied_rows`・`failed_rows`・`duration_ms`（取り込みを作ってから終えるまで） | ファイル名と行の値 |
| 上の表に無いイベント | 無し（`name`・`context`・`timestamp` だけを書く） | `payload` と `tags` |
| ヘルスチェック（`Rails::HealthController`）の要求の開始と終わり | 行を書かない | 全体。`silence_healthcheck_path` は `Rails.logger` を黙らせるだけで、`Rails.event` を止めない |

アプリが出すイベントのペイロードには、ID・コード・件数・時間だけを入れ、メールアドレス・氏名・自由記述（取消の理由・在庫調整の理由）を入れない。`filter_parameters` に `name` を足すと `item_name`・`operation_name` まで消えるので、氏名はこの規則で守る。

`Rails.event` は、ハッシュのペイロードにだけ `filter_parameters` を掛ける。ハッシュでないペイロードが購読者に届くのは、イベントのオブジェクトを `notify` に渡したときで、購読者はそれを例外にする。Rails は `Rails.event.raise_on_error` を `consider_all_requests_local` から決める（開発とテストで真、本番で偽）ので、購読者の例外は、開発とテストでは呼び出し元まで上がり、本番ではエラー通知に送られて行が書かれない。この 2 つの設定を変えない。

`active_record.sql` は `Rails.event` のデバッグのイベントで、デバッグのモード（開発の環境）でだけ出る。表に無いので、SQL の本文は書かない。

### 止めたフレームワークの文字列のログ

JSON の書式は、文字列の中の秘密やクエリの本文を消さない。そこで、値を文字列のまま `Rails.logger` に書くフレームワークの経路を、書式に頼らず止める。Rails 8.1.4・Solid Queue 1.7.0・Ruby 3.4.11 で止めた経路は次の 5 つで、本番とテストだけで止める。

| 経路 | 書いていたもの | 止め方 |
|---|---|---|
| `ActionController::LogSubscriber`・`ActionDispatch::LogSubscriber`・`ActiveJob::LogSubscriber` | 構造化イベントと同じ内容を、params・ジョブの引数・例外のメッセージ込みの文字列で | `config.after_initialize` で購読を外す |
| `ActionMailer::LogSubscriber` | メールの送信の失敗を、例外のメッセージ込みで | 同上 |
| `SolidQueue::LogSubscriber` | ワーカーのスレッドで上がったジョブの例外を、メッセージ込みで（`Error in thread`）。ワーカーの起動と停止の行も、この購読が書く | 同上。ジョブの失敗は `active_job.completed` の `exception_class` とエラー通知に残る |
| `Rails::Rack::Logger` | 要求の開始の行に `request.filtered_path`。`filter_parameters` は名前で隠すだけなので、URL の `query`・`variables` の値が残る | ミドルウェアから外す。外して失う `request.action_dispatch` の計装は、Rails 8.1.4 の中に購読者が無い |
| `ActionDispatch::DebugExceptions` | 捕まえた例外のメッセージとバックトレース（`fatal`） | ミドルウェアから外す。本番ではこれが唯一の役目である。例外は `ActionDispatch::Executor` がエラー通知に送り、ログには `action_controller.request_completed` の状態コードが残る |

残る文字列のログの経路は、`debug` の水準のもの（SQL とそのバインド値・JSON の解析に失敗した要求の本文など）と、本デモが使わない機能（テンプレートの描画・ホストの制限・リダイレクト・ストリーミング）のものである。

止める経路は名指しの一覧なので、依存を上げて値を文字列で書く購読かミドルウェアが加わっても、それだけでは止まらない。そこで `spec/platform/logging_spec.rb` が、子のプロセスで本番の環境を初期化し、`ActiveSupport::LogSubscriber` の購読のクラスの集合・`Rails.event` の購読者・ミドルウェアの並びが、許した一覧と一致することを確かめる（[ADR 008](../adr/008-本番に残すログの購読とミドルウェアを許した一覧で守る.md)）。依存を上げてこの spec が落ちたら、増えた購読かミドルウェアのソースを読む。値を文字列で書くなら `Platform::Logging` で外して上の表に足し、書かないなら spec の許した一覧に足す。`ActiveSupport::Notifications` を直接購読するものと、gem の中から `Rails.logger` を直接呼ぶものは一覧に出ないので、依存を上げる PR で変更点を読んで見る。

> Ruby 3.3.3 から 3.4.11 へ上げ、`bundle update` を流した前後で、本番の環境の購読とミドルウェアの並びを比べた。Rails 8.1.4・Solid Queue 1.7.0 は版の制約の中の最新で変わらず、違いは使っていない部品を外して消えた Active Storage の購読 2 つだけだった。

`debug` の行は値を文字列のまま書くので、本番では水準を `info` より細かくできない。水準は環境変数 `RAILS_LOG_LEVEL` で決め、既定は `info`、許す値は `info`・`warn`・`error`・`fatal`・`unknown` である。`production.rb` は `config.after_initialize` で、初期化の後の `Rails.logger` の水準を `Platform::Logging.verify_production_level!` に通し、`info` より細かければ起動を止める。環境変数ではなく最終の水準を見るので、`config.log_level` を直接 `:debug` にしても起動しない。止めるのは設定からの指定だけで、初期化の後にコードで水準を変える・ロガーを差し替える経路はコードレビューで止める（OI-36）。

### 構成の入口：文脈のミドルウェアとログの書式

要求の文脈を設定するミドルウェアの登録と、ログの書式の設定を分ける。文脈はどの環境でも要るが、JSON の書式は本番とテストだけに掛けるからである。

- **文脈のミドルウェア**：`application.rb` が、全環境で `config.middleware.insert_before Rails::Rack::Logger, Platform::RequestContext` を呼ぶ。開発では `Rails::Rack::Logger` が直後に残り、要求の開始の行を、文脈を設定した後に Rails の文字列のまま書く。
- **ログの書式**：`Platform::Logging.configure!(config, io)` が、`config.logger` の設定・`config.log_tags` の消去・`Rails::Rack::Logger` と `ActionDispatch::DebugExceptions` の削除・購読の解除をまとめて行う。`environments/production.rb`（`STDOUT`）と `environments/test.rb`（`log/test.log`）がこれを呼ぶ。Rails は `config.middleware` の挿入をすべて当ててから削除を当てるので、`Rails::Rack::Logger` を消しても、`Platform::RequestContext` はその位置に残る。テストの環境も呼ぶのは、ミドルウェアの構成が起動の時点で決まり、spec の中から変えられないからである。ログの衛生の spec（`spec/requests/log_hygiene_spec.rb`）は、本番と同じ構成を通る。開発の環境は、読みやすさのため Rails の文字列のログのままにする。

設定の時点では自動読み込みが効かないので、`Platform::Logging`・書式・購読者・`Platform::RequestContext` は `packs/platform/lib/platform/` に置き、`application.rb`・環境のファイル・`initializers/event_log.rb` から `require_relative` で読む。

開発の環境のミドルウェアの並びは、次で確かめる。

```sh
bin/rails middleware | grep -A1 'Platform::RequestContext'   # 次の行が Rails::Rack::Logger
```

### 文脈を設定する位置

`context` の項目は、次の場所で `Rails.event.set_context` が設定する。同じ場所で、エラー通知の文脈（`Rails.error.set_context`）にも `request_id`・`tenant_id`・`user_id`・`correlation_id` を設定し、エラー通知にテナント ID を付ける（[decisions.md](../architecture/decisions.md) 2 章）。

| 項目 | 設定する場所 |
|---|---|
| `request_id`・`correlation_id`（要求） | `Platform::RequestContext`。利用者の要求は一連の処理の始まりなので、`request_id` を相関 ID にする |
| `tenant_id`・`user_id`・`graphql_operation` | `GraphqlController`（認証の後、スキーマを実行する前）。操作名が無ければ `anonymous`、GraphQL の名前の形でなければ書かない |
| `job_id`・`job_class`・`queue`・`tenant_id`・`correlation_id` | `ApplicationJob#perform_now`（ジョブの付帯情報から） |
| `event_id`・`event_name`・`causation_id` | `ApplicationJob#perform_now`（`Contracts::EventJob` の付帯情報から。因果 ID は届いたイベントの `event_id`） |

文脈を設定する区間は、Rails がイベントを出す区間を含めなければならない。

- **要求**：Rails 8.1.4 は、`action_controller.request_started` を `before_action` より前の `process_action` の入口で出す。そこで `Platform::RequestContext` を、`ActionDispatch::RequestId` の後、`ActionDispatch::Executor` の内側に置く。セッションはこの位置より内側で読まれるので、`request_started` に付くのは `request_id` と相関 ID だけで、`tenant_id`・`user_id`・`graphql_operation` は `request_completed` から付く。
- **GraphQL**：`GraphqlController` は、スキーマを実行する前に文脈を設定する。`Rails.event` の文脈は Fiber のストレージにあり、Dataloader が作る Fiber は作られた時点の値を写して持つ。Fiber の中で設定した値は、親に戻らない。
- **ジョブ**：`active_job.started` は perform のコールバックより前に、`active_job.completed`・`retry_scheduled`・`discarded` は `perform_now` の計装の中で出る。そこで `ApplicationJob` は `perform_now` を上書きし、`super` の前に文脈を設定する。ワーカー（`ActiveJob::Base.execute` から `perform_now`）と直接の `perform_now` の両方がここを通る。呼び出し元の文脈は、ログとエラー通知のどちらも引き継がず、ジョブの文脈に置き換える。文脈の値は、引数ではなくジョブの付帯情報から読み、ここで引数を復元しない。Rails 8.1.4 は、引数の復元を `super` の中の、再試行・破棄の処理と計装の内側で行う。先に復元すると、復元の失敗（`ActiveJob::DeserializationError`）が `retry_on`・`discard_on`・`after_discard` を通らず、`active_job.completed` も出ない。

ワーカーの実行器は、`perform_now` を抜けて文脈が戻った後に例外をエラー通知に送る。そこで `ApplicationJob#perform_now` は、呼び出し元へ上がる例外を、ジョブの文脈の中でエラー通知に送ってから上げる。エラー通知は同じ例外の 2 回目の通知を捨てる。

### 文脈の後始末

Rails は、executor で包まれた処理（Web の要求と、ワーカーが動かすジョブ）の終わりに、`Rails.event` の文脈を空にし、エラー通知の文脈を空にする。テストの example と、`perform_now` で直接動かすジョブは executor で包まれないので、文脈が次の処理へ持ち越される。そこで次の 2 つで後始末する。

- `ApplicationJob#perform_now` は、実行の前の `Rails.event.context` とエラー通知の文脈（`ActiveSupport::ExecutionContext`）を丸ごと退避し、例外の経路も含めて `ensure` で丸ごと戻す。エラー通知の文脈は、`Rails.error.set_context` が渡した項目だけを書き換えるので、項目の集合ごとジョブの項目（`job`・`tenant_id`・`correlation_id`）に置き換える。`ActiveSupport::ExecutionContext.clear` は `Current` の値と入れ子のスタックも捨てるので使わない。入れ子のジョブも、抜けた後は外側のジョブの文脈に戻る。この置き換えと戻し方は、Rails が文脈をスレッドごとに持つ（`config.active_support.isolation_level` が既定の `:thread`）ことを前提にする（OI-35）。
- `spec/support/log_context.rb` は、各 example の後で `Rails.event.clear_context` と `ActiveSupport::ExecutionContext.clear` を呼ぶ。

### 相関 ID と因果 ID

- **相関 ID**（`correlation_id`）：一連の処理の始まりで 1 つ決め、最後まで同じ値を運ぶ。利用者の要求では `request_id` を、要求の外で発行したイベント（相関 ID の無い文脈）ではそのイベントの `event_id` を相関 ID にする。mutation の入口は要求（`GraphqlController`）だけなので、mutation はいつも相関 ID を持つ。監査の行は相関 ID を必須にする（[data-model.md「監査ログ（`platform`）」](../architecture/data-model.md#監査ログplatform)）ので、要求の外から mutation を流す入口を足す人は、その入口の相関 ID の始め方を同じ変更で決める。決めないと、監査の行の INSERT が失敗して操作ごと戻る（OI-42）。
- **因果 ID**（`causation_id`）：いまの処理を直接引き起こしたものの ID。要求では空、イベントの受け手では届いたイベントの `event_id` である。
- **付帯情報**：`ApplicationJob` は、ジョブを作った時点（`initialize`）の相関 ID とテナント ID を付帯情報に入れる。`Contracts.publish` は、ジョブを作った後、登録の前に、付帯情報をイベントのもの（[data-model.md「イベントの受け口と冪等キー」](../architecture/data-model.md#イベントの受け口と冪等キー)）に置き換える。付帯情報は直列化の最上位の項目（`"app_metadata"`）に入るので、再試行の登録にも引き継がれる（[ADR 005](../adr/005-イベントのジョブをトランザクション内で登録する.md) 決定 3）。付帯情報の無いジョブの扱いは、イベントのジョブとそれ以外で分かれる。
  - **イベントのジョブ**：付帯情報を必須とする。`Contracts::EventJob` は、受信の監査の行と配送の遅れの計測に使う項目（`Contracts::EventJob::REQUIRED_METADATA`）が 1 つでも無ければ、受け手を動かさずに `Contracts::EventJob::MissingMetadata` で失敗する。受信の監査の行を書けないまま受け手の書き込みだけを残すと、相手テナントに効果が及ぶ書き込みが記録されなくなるからである（[graphql-schema.md「監査ログ」](../architecture/graphql-schema.md#監査ログ)）。
  - **それ以外のジョブ**：項目の無いジョブも、付帯情報の文脈を設定せずに動かす。

受け手の中で発行するイベントは、同じ相関 ID と、因果 ID として受け手が受け取ったイベントの `event_id` を持つ。これで、発注側の `placePurchaseOrder` の要求 → 「発注登録」 → 受注側の購買のイベントの受け手 → 「受注確定」 → 購買の受け手、の全ログが同じ相関 ID を持つ（`spec/contracts/correlation_spec.rb`）。テナントは途中で変わるので、相関 ID でログを引けるのは運用者だけで、テナントの利用者には相手側のログを見せない。

開発の環境で、2 社のイベントの配送が同じ相関 ID で並ぶことは、`bin/dev` と `bin/jobs` を動かして発注を 1 件登録し、次で確かめる。

```sh
grep <相関 ID> log/events.log
```

## メトリクス

運用者は、GraphQL の操作の時間、キューの滞留と待ち時間、イベントの配送の遅れ、外部の呼び出しの失敗と 429、取り込みの速さを、Prometheus が Web とワーカーの exporter から引いた数値で見る。値はログと同じ `Rails.event` のイベントから作る。`initializers/metrics.rb` が、メトリクスの定義と、イベントを数える購読者 `Platform::MetricsSubscriber`（`packs/platform/lib/platform/`）の登録を 1 か所で行う。キューの滞留だけはイベントが無いので、Prometheus が引きに来た時点で Solid Queue の表を数える。

メトリクスの道具は Yabeda と `yabeda-prometheus` にする。Prometheus が引きに来る形なので、収集器（Collector）を立てずに手元とデモで確かめられる。OpenTelemetry の Ruby のメトリクスの SDK は、まだ 1.0 に達していない。分散トレースが要るか、監視の基盤が OTLP で受けるなら OpenTelemetry に移る。値の出どころは購読者の 1 つなので、移るときは出口のライブラリを替えるだけで済む。

> opentelemetry-metrics-sdk の最新は 0.20.0 だった（2026 年 10 月に rubygems.org で確かめた）。

### メトリクスとラベル

| メトリクス | 種類 | ラベル | 出どころ |
|---|---|---|---|
| `graphql_operation_duration_seconds` | ヒストグラム | `operation`・`operation_type`・`outcome`（`ok`・`user_error`・`error`） | `graphql.operation_completed` の `duration_ms` と `result`（`success` を `ok` に写す） |
| `graphql_top_level_errors_total` | カウンタ | `operation`・`code`・`reason` | 同じイベントの `error_codes` と `forbidden_reasons`。`FORBIDDEN` の 1 件ごとに出どころを 1 つ当て、ほかのコードの `reason` は `none` にする |
| `job_duration_seconds` | ヒストグラム | `queue`・`job_class` | `active_job.completed` の `duration`（ミリ秒） |
| `job_queue_latency_seconds` | ヒストグラム | `queue` | `active_job.started` のイベントの時刻 − `enqueued_at`。`enqueued_at` の無いジョブ（登録を通らずに `perform_now` したもの）は数えない |
| `event_delivery_lag_seconds` | ヒストグラム | `event` | `contracts.event_handled` の `delivery_lag_ms` |
| `queue_ready_jobs`・`queue_blocked_jobs`・`queue_claimed_jobs`・`queue_failed_jobs` | ゲージ | `queue` | 引きに来た時点で、Solid Queue の 4 つの実行の表をキューごとに数える。`claimed` は実行中のジョブである。`config/queue.yml` のワーカーのキューと、そのプロセスで一度でも数えたキューは、ジョブが無くても 0 を書く。書かないと、最後に数えた値が残る |
| `external_requests_total` | カウンタ | `provider`・`status` | `notifications.provider_responded` |
| `notification_acceptance_seconds` | ヒストグラム | `kind` | `notification.accepted` の `acceptance_ms` |
| `notification_failures_total`・`notification_dropped_total` | カウンタ | `kind`・`reason` | `notification.delivery_failed`・`notification.best_effort_dropped` |
| `import_rows_total` | カウンタ | `kind`・`result`（`applied`・`failed`） | `imports.chunk_applied` の `applied_rows`・`failed_rows` |
| `import_duration_seconds` | ヒストグラム | `kind`・`size`（10,000 行以下は `small`、超えれば `large`） | `imports.finished` の `duration_ms` と `total_rows`。行を数える前に失敗した取り込みは `total_rows` が無く、反映した行が無いので `small` にする |

メトリクスを足す人は、ラベルにテナント ID・ユーザー ID・伝票の ID を入れない。値の種類が増え続けて保存が膨らみ、メトリクスの基盤にテナントの情報が流れるからである。テナントごとの調査は、ログの相関 ID で行う。`spec/platform/metrics_subscriber_spec.rb` が、どのラベルの名前にも `tenant`・`user`・`_id` で終わる名前が無いことを確かめる。

`operation` には、クライアントが自由に付ける `operationName` をそのまま使わない。`config/graphql_operations.yml` に登録した名前だけを使い、登録の無い名前・名前の無い操作・種類の違う操作に付いた登録の名前は `other` にする。登録の表は `queries` と `mutations` に分ける。`queries` は画面の問い合わせ（`frontend/graphql/`）の query の操作名と、`mutations` は mutation の操作名と一致させ、spec がそれを確かめる。

ヒストグラムのバケットは、SLO の閾値（`graphql_operation_duration_seconds` の 0.5 秒と 1 秒、`event_delivery_lag_seconds` の 60 秒、`notification_acceptance_seconds` の 900 秒、`import_duration_seconds` の 300 秒）を境界に含める。バケットを指定しないと `prometheus-client` の既定（最大 10 秒）になり、閾値の割合を取れない（yabeda-prometheus 0.9.1 の `lib/yabeda/prometheus/adapter.rb` の `register_histogram!`）。閾値を変える人は、バケットも同じ変更で直す。spec は、閾値ちょうどの値と閾値を超える値が別の `le` に数えられることを確かめる。

### exporter と値の置き場

exporter は、Web とワーカーで 1 つずつ、別のポート（Web は 9394、ワーカーは 9395）で立てる。ポートは内部のネットワークにだけ開き、公開のロードバランサーに出さない。Rails のルートには `/metrics` を置かない。exporter を立てるのは、環境変数 `METRICS_PROCESS`（`web`・`jobs`）でプロセスの種類を示したプロセスだけである。`METRICS_PROCESS` の無いプロセス（rake タスク・console と、設定しない開発のサーバー）は exporter を立てず、値をプロセスのメモリに置く。test の環境では、設定があっても立てない。

| プロセス | 立てる場所 | 立てる時機 |
|---|---|---|
| Web（`METRICS_PROCESS=web`） | `puma.rb` の `after_booted` | 起動の後に 1 回。Puma を単一のモードで動かし、fork しない。`puma.rb` に `workers` を置かず、環境変数 `WEB_CONCURRENCY` にクラスタのモードになる値（正の数と `auto`）を設定しない。未設定と `0` は単一のモードで起きる。Puma は `WEB_CONCURRENCY` があればクラスタのモードで起き（puma 8.0.2 の `lib/puma/configuration.rb`）、`after_booted` が worker の fork の後に動くので、空にしたディレクトリが worker の値を消す。初期化子に置くと、`config/environment` を読む `bin/jobs`・rake タスク・console でも立つ |
| ワーカー（`METRICS_PROCESS=jobs`） | `initializers/metrics.rb` の `SolidQueue.on_start` | supervisor が worker・dispatcher・scheduler を fork する前に 1 回（solid_queue 1.7.0 の README「Lifecycle hooks」） |

`yabeda-prometheus` の exporter は、ポートを `PROMETHEUS_EXPORTER_PORT`（無ければ `PORT`）で、アドレスを `PROMETHEUS_EXPORTER_BIND`（無ければ `0.0.0.0`）で決め、引数では渡せない（`lib/yabeda/prometheus/exporter.rb`）。`PORT` は Puma も使うので、`Platform::Metrics.start_exporter!` は、`PROMETHEUS_EXPORTER_PORT` の無いプロセスと、`METRICS_PROCESS` がプロセスの種類と違うプロセスと、`WEB_CONCURRENCY` にクラスタのモードになる値（正の数と `auto`）を設定した Web のプロセスの起動を止める。Web は `after_booted` の例外で止まる。ワーカーは、solid_queue 1.7.0 の `LifecycleHooks#run_hooks_for` がフックの例外を拾って起動を続けるので、`Platform::Metrics.start_worker_exporter!` が worker を fork する前にプロセスを終える。exporter は Rack 3 では `Rackup::Handler::WEBrick` で立つが、`webrick` は `yabeda-prometheus` の依存に無いので、Gemfile に書く。

fork した子のプロセスも値を書くので、`METRICS_PROCESS` のあるプロセスは、値を `prometheus-client` の `DirectFileStore` で `tmp/metrics/<環境>/<METRICS_PROCESS>` に書き、exporter がまとめて読む。

- **ディレクトリを選ぶ時点**：store はメトリクスを登録する時点で決まる（`adapter.rb` の `store_settings`）ので、`initializers/metrics.rb` が Yabeda の設定より前に選ぶ。
- **空にする時点**：exporter を立てる直前の 1 回だけである。初期化子で空にすると、同じ設定で後から起きた別のプロセスが、動いているプロセスの値を消す。
- **キューのゲージ**：収集のブロックは、どちらの exporter の読み出しでも動くので、`METRICS_PROCESS` が `jobs` のプロセスにだけ登録する。ゲージは supervisor の 1 つのプロセスだけが書くので、集計を `aggregation: :most_recent` にする。`DirectFileStore` のゲージの既定の集計は、プロセスごとの値を `pid` のラベルで分けて出す。

開発の環境では、次で値が出ることを確かめる。`queue_ready_jobs` の行に `pid` のラベルが無い。

```sh
PROMETHEUS_EXPORTER_PORT=9394 METRICS_PROCESS=web bin/rails server   # GraphQL の問い合わせを 1 回流す
curl -s localhost:9394/metrics | grep graphql_operation_duration_seconds_bucket
PROMETHEUS_EXPORTER_PORT=9395 METRICS_PROCESS=jobs bin/jobs          # イベントを 1 件流す
curl -s localhost:9395/metrics | grep -E 'job_duration_seconds_count|queue_ready_jobs'
```

## 環境ごとの設定

`environments/` の 3 ファイルは、ログの書式（[ログ](#ログ)）と、N+1 の検出（Bullet。[graphql-schema.md「ページングと N+1」](../architecture/graphql-schema.md#ページングと-n1)）と、通知のメールの送信先（`config.x.notifications.*`。[ジョブ](#ジョブ)）と、本番の `assume_ssl` と、`test.rb` の起動の時の読み込みの条件（下の 1 つ目）を足し、使っていない部品の設定（`active_storage.service` と Action Cable の生成時のコメント。[使っていない機能の設定](#使っていない機能の設定)）と、本番の SMTP の生成時のコメントを消したほかは生成のままである。本番のメールは SMTP ではなく SendGrid の API へ送るからである。本デモの読み方で知っておくとよいのは次の 3 つ。

- **`test.rb` の `eager_load = ENV["CI"].present? || ENV["E2E_EAGER_LOAD"].present?`**：CI ではテストの前に全コードを読み込む。`packs/*/app/` のファイル名と定数名が合わないなど、自動読み込みの誤りは CI で落ちる。E2E の Rails は、手元でも起動の時に読み込む。`frontend/e2e/start-rails.sh` が `E2E_EAGER_LOAD=1` を渡すので、手元の E2E も CI と同じく読み込んでから `/up` に答え、自動読み込みの誤りも手元で落ちる。読み込まないと、最初の要求が定数を読み込む時間だけ遅れ、ログインの後の画面の移りが期待の待ちを超えることがある。`CI` そのものは渡さない。`CI` は CI の上で動いていることを表し、読み込みのほかにも gem や道具が見て振る舞いを変えうるからである。変数を外しても手元の E2E は通るので、`spec/platform/e2e_eager_load_spec.rb` が、子のプロセスで `E2E_EAGER_LOAD=1` を渡したときだけ `eager_load` が真になることと、`start-rails.sh` が `bin/rails` を呼ぶ行より前に `export E2E_EAGER_LOAD=1` を持つことを確かめる。
- **`production.rb` に Solid Queue の `connects_to` が無い**：[ジョブ](#ジョブ) のとおり、意図して書いていない。
- **`production.rb` の `assume_ssl = true`**：本番の環境の要求を https として扱う。TLS は前段（公開の配置では Cloudflare）で終わり、Rails には Next のサーバーから http で届く。actionpack 8.1.4 は `request.ssl?` が偽の応答に `Secure` の Cookie を書かない（`lib/action_dispatch/middleware/cookies.rb` の `write_cookie?`）ので、このままではログインの応答にセッションの Cookie が無い。Rails はこのとき `ActionDispatch::AssumeSSL` をミドルウェアの先頭に足すので、`spec/platform/logging_spec.rb` の許した一覧にも入れてある（[ADR 009](../adr/009-デモを流用元と同じRaspberryPiのk3sに置き共有のデータを毎日作り直す.md) 決定 2）。

本番の環境は、公開の配置（`deploy/`）が渡す次の環境変数で振る舞いを変える。どれも、渡さなければいまの本番の振る舞いのままになる。`spec/platform/production_boot_spec.rb` が、子のプロセスで本番の環境を起こして確かめる。

| 環境変数 | 読む場所 | 効き目 | 渡さないとき |
|---|---|---|---|
| `DB_HOST`・`DB_PORT` | `database.yml` の `production` | 2 つのロールの接続先 | ホストを持たず、ポートは 5432 |
| `NOTIFICATIONS_PROVIDER` | `production.rb` | `file_system` なら通知のメールを `tmp/mails/` に書き、外へ送らない。公開の配置のアカウントのメールアドレスは実在しないからである。`sendgrid` と `file_system` のほかの値は、打ち間違いで黙って SendGrid に送らないように起動で落とす | SendGrid |
| `SHARED_DEMO_ACCOUNTS` | `application.rb` | `1` ならログアウトでセッションの世代を進めない（[graphql-schema.md「1 回のリクエストがたどる道」](../architecture/graphql-schema.md#1-回のリクエストがたどる道)1） | 世代を進める |
| `DEMO_WORLD_ENABLED` | `Platform::DemoWorldGate` | `1` なら本番の環境でもデモの世界を作る公開 API を呼べる。公開の配置は毎日の作り直しにだけ渡す（[data-model.md「RLS」](../architecture/data-model.md#rls)） | 呼ぶと例外 |

## CI の工程

`ci.rb` は、`bin/ci` が順に流す工程を `step` で並べる。生成のままの工程から、次のように変えた。

| 工程 | 生成のまま | 本デモ | 理由 |
|---|---|---|---|
| Packages: packwerk | — | `bin/packwerk validate && bin/packwerk check` | 依存の向きと公開 API の限定を強制する（[ADR 002](../adr/002-packwerkを初日からCIで強制する.md)） |
| Ledgers | — | `bin/check-open-items` | 残件と改善の候補の台帳の形と、ID の参照を確かめる（[dev-cycle.md「機械で守ること」](dev-cycle.md#機械で守ること)） |
| Ledgers: commit references | — | `bin/check-commit-refs` | 台帳・証跡・引き継ぎに書いた SHA が HEAD の祖先かを確かめる（[dev-cycle.md「機械で守ること」](dev-cycle.md#機械で守ること)） |
| GraphQL: schema compatibility | — | `bin/check-schema-compat` | `origin/main` との分岐点からの、非推奨を経ない破壊的変更を止める（[graphql-schema.md「互換の判定」](../architecture/graphql-schema.md#互換の判定)） |
| Tests | `bin/rails test` | `bin/rails db:test:prepare && COVERAGE=1 bundle exec rspec --format progress --format json --out tmp/rspec.json` | テストに RSpec を使う。層ごとの件数を数えるため、JSON の出力も書く。分岐の網羅率を同じ実行で測る |
| Tests: branch coverage | — | `bin/check-branch-coverage` | `origin/main` との分岐点からの差分の、どの example も通らない分岐を警告にする（[testing.md「分岐の網羅率の警告」](testing.md#分岐の網羅率の警告)） |
| Tests: layers | — | `bin/test-layers tmp/rspec.json` | テストの層ごとの件数・割合・時間を報告し、未分類のファイルを止める（[testing.md「テストの層」](testing.md#テストの層)） |
| Schema | — | `bin/check-structure` | `structure.sql` の往復を確かめる（[ADR 001](../adr/001-スキーマ管理にridgepoleを採用しない.md)） |
| Alerts | — | `bin/check-alerts` | 警報の規則の式と、テストの系列での発火と不発火を、Prometheus のイメージの promtool で確かめる（[../slo.md](../slo.md)） |

画面（`frontend/`）の検査は `bin/ci` の工程に無く、`.github/workflows/ci.yml` の `frontend` のジョブ（`npm ls --all`・`npm run codegen:check`・`lint`・`typecheck`・`test:unit`）と `e2e` のジョブ（`npm run test:e2e`）が流す。手元では `README.md`「画面」の手順で流す。公開の配置のマニフェストの照合（`manifests` のジョブ）とイメージの組み立て（`images` のジョブ）と GHCR への push（`publish` のジョブ）も `bin/ci` に無く、手元では `kubectl kustomize deploy` と `deploy/README.md` の手順で確かめる。

CI のジョブを足すか重くする人は、PR の CI が最も長いジョブで 10 分の内に終わるようにする。PR の CI の時間は、担当が結果を待って次へ進むまでの時間だからである。どのジョブも、PR と main への push のたびに流し、変えたファイルで契機を絞らない。`images` のジョブも、キャッシュが空でも予算の内で `test` のジョブより短く終わり、ワークフロー全体を延ばさないので、毎回流す。契機を絞ると、絞る条件の保守（イメージに入るファイルの一覧）が要り、漏れた変更を確かめないまま通し、`publish` が skip されたジョブを待つ条件も要るからである。予算を超えるジョブを足すか、`images` が予算を超えるようになったときだけ、確かめる対象を変えた PR と main への push でだけ流す条件を足し、その形を `adr/009`「見直す条件」に従って決める。

> `images` のジョブは、arm64 のランナー（M42、PR #74）で、キャッシュが空のときに 4 分 10 秒、キャッシュが効くときに 59 秒だった。amd64 のランナーの QEMU の上では、キャッシュが空のときに 25〜35 分かかった（サイクル 05）。

GHCR にイメージを置くのは `publish` のジョブだけで、main への push で、ワークフローのほかのすべてのジョブが成功したときだけ流れる。テストの落ちた commit のイメージを置かないためである。`images` は組み立てと確かめだけにし、`publish` は同じキャッシュから組み立て直して push する。ジョブを足す人は、`publish` の `needs` にも足す。`publish` の `if:` は `success() && github.event_name == 'push'` と書き、`success()` を明示する。`success()` は `needs` のどれかが落ちたか、取り消されたか、skip されたときに偽になり、そのジョブを skip する（GitHub の文書の「Workflow syntax for GitHub Actions」の `jobs.<job_id>.needs`：「If a job fails or is skipped, all jobs that need it are skipped unless the jobs use a conditional expression that causes the job to continue.」）。GitHub は状態の関数を含まない `if:` にだけ `success()` を足すので、書かなくても同じ守りになるが、明示すると守りが YAML の行で読める。`failure()`・`cancelled()`・`always()` を足すと、落ちたか取り消された `needs` でも流れて push するので書かない。`success()` を否定するか（`!success()`・`!(success() && …)`）、論理和でつなぐか（`success() || …`）、比べるか（`success() == false`・`false == success()`・`success() < 1`）、関数の引数か添字に入れて真の値に変えても（`format('{0}', success())`）、状態の関数を含むので GitHub は `success()` を足さず、落ちた `needs` でも流れるので書かない。`needs` に無いジョブは、落ちても push を止めない。`continue-on-error` も、ジョブの段では落ちたジョブの `needs` の結果を、ステップの段では落ちたステップのジョブの結果を `success` にするので、どのジョブにもステップにも書かない。ジョブの段の `if:` は `publish` にだけ書く。ほかのジョブに契機を絞る `if:` を足すと、push でそのジョブが skip され、`publish` も skip される。`publish` の `needs` がほかのすべてのジョブちょうどであること、`continue-on-error` を持つジョブとステップが無いこと、ジョブの段の `if:` を持つのが `publish` だけで、その `if:` が `success()` を比べず関数の引数にも入れずに含み、`!` と `||` と `failure`・`cancelled`・`always` を含まないこと、push と `packages: write` を持つジョブが `publish` だけで、ワークフローの最上位の権限が `contents: read` だけであることは、`spec/platform/ci_checks_spec.rb` が確かめる。

どのジョブも、ランナーを OS の版の数字を含む名前（amd64 は `ubuntu-24.04`、arm64 の `images` と `publish` は `ubuntu-24.04-arm`）で指定する。`ubuntu-latest` は GitHub が日程で版を上げ、CI が通るかを確かめないまま版が変わるからである。版の形と arm64 のジョブは `spec/platform/ci_checks_spec.rb` が確かめる。版を上げる人は、GitHub がいまの版のランナーの廃止を告知したとき（GitHub の changelog と、`actions/runner-images` の告知）か、Ubuntu のいまの版の標準の保守が終わる前に、すべてのジョブの `runs-on` を 1 つの PR で上げ、その PR の CI がすべて通ることを確かめる。

依存の版上げの PR は、Dependabot が週に 1 回、`.github/dependabot.yml` のまとめ方で開く（設定の鍵の意味は GitHub の文書の [Dependabot options reference](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference) の `groups` と `ignore`）。bundler と npm は、小版と修正版をエコシステムごとに 1 本の PR にまとめ、主版の上げはまとめずに 1 本ずつ開かせて、破壊的な変更を 1 本ずつ CI で確かめる。npm の `react`・`react-dom`・`@types/react`・`@types/react-dom` は、主版も含めて組で 1 本にする。`react-dom` は peer に同じ版の `react` を求め、1 本ずつでは `npm ci` が ERESOLVE で落ちるからである。Dependabot は依存を最初に当たったまとまりに入れるので、組のまとまりは小版と修正版のまとまりより先に置く。組のまとまりは `update-types` を絞らず、組の依存を `exclude-patterns` に入れない。外れた更新は 1 本ずつ開き、組が分かれるからである。0 系の依存（いまは `cn`・`class-variance-authority`）は、小版と修正版のまとまりの `exclude-patterns` に入れて 1 本ずつ開かせる。0 系の小版の上げは破壊的な変更を含みうるからである。github-actions は、変えるのがワークフローの 1 ファイルで、その PR の CI がそのまま確かめるので、主版も含めてすべてを 1 本にまとめる。まとめた PR が 1 つの更新で落ちたまま何週も止まったら、落ちる依存をまとまりから外す。どのエコシステムもまとまりを持つこと、小版と修正版のまとまりが主版を含まないこと、組のまとまりの位置と主版を含むこと、0 系の依存の除外は、`spec/platform/dependency_updates_spec.rb` が確かめる。0 系の依存は `frontend/package.json` の範囲から集めるので、画面に 0 系の依存を足して `exclude-patterns` に足し忘れると落ちる。

画面の Node の主版は、`frontend/package.json` の `engines`（`^<主版>.<小版>`）が正本である。CI の `actions/setup-node` を使うすべてのステップの `node-version`、`frontend/Dockerfile` の `NODE_VERSION`、`@types/node` の範囲が同じ主版であることと、`@types/node` の範囲が 1 つの主版に収まる形であることを、同じ spec が確かめる。型定義の主版を実行の主版より上げると、実行の版に無い API が型検査を通るので、`@types/node` の主版の上げは `dependabot.yml` の `ignore` にしてある（これも同じ spec が確かめる）。Node の主版を上げる人は、この 4 か所を 1 つの PR で上げる。画面の検査の道具が受け付けない主版の上げ（いまは `typescript` 7 と `eslint` 10）の PR は、`ignore` にせず開いたままにし、上げられるようになったことに気づけるようにする。`typescript` は、`typescript-eslint` が新しい主版を受け付けるまで `npm run lint` で落ちる。`eslint` は、`eslint-config-next` が入れるプラグインの peer の範囲が新しい主版を含むまで、`frontend` のジョブの `npm ls --all` で落ちる。`npm ci` は入れ子の依存の peer の外れを止めないので、このステップが無いと `eslint` の PR の CI は通って見える。`npm ls --all` を `npm ci` の後に同じ `frontend` の置き場で流すことは `spec/platform/ci_checks_spec.rb` が確かめる。開いた PR は、道具の側を上げても自動では流れ直さないので、道具を上げた人は PR の CI を流し直す。

GitHub Actions は `bin/ci` を呼ばず、同じ検査を `.github/workflows/ci.yml` から直接流す（[bin.md「CI が使うもの」](bin.md#ci-が使うもの)）。

ワークフローが流す `bin/` のコマンドの名前は、`config/ci.rb` の工程と `implementation-plan.md`「共通の完了条件」の一覧にもあることを `spec/platform/ci_checks_spec.rb` が確かめる。実装者は完了条件の一覧のとおりに手元で流すので、一覧に無い検査は CI で初めて落ちるからである。ステップの順と契機ごとの `BASE_REF` の式、コマンドの引数は、spec で守らない。YAML の式を文字列で照らす spec は、式の書き換えに追従できないからである。この節で spec が確かめると書いたもの（`npm ls --all` の順と置き場、`publish` の `if:` が `success()` を比べず関数の引数にも入れずに含み、`!` と `||` と `failure`・`cancelled`・`always` を含まないことなど）は、壊れると確かめないまま通すか、確かめていないイメージを置く規則なので、例外として照らす。式の形は照らさず、含む・含まないの条件で照らす。配線を変えた人は、その PR で、検査が落ちるべき変更を作業ツリーに入れて CI と同じコマンドで落ちることを手で確かめ、証跡に書く（OI-59）。

## 使っていない機能の設定

`rails new` は、本デモが使わない Rails の部品と gem も読み込む。読み込まれた部品があると、読む人や AI がそれを使える前提で設計するので、使わない部品は読み込まない。外したものと残したものは次のとおりである。

| 部品 | 扱い | 理由 |
|---|---|---|
| Active Storage・Action Mailbox・Action Text・Action Cable | 外した。`application.rb` で読み込まず、`environments/*.rb` の `active_storage.service`、`storage.yml`・`cable.yml`、保存先の `storage/` も置かない | ファイルの添付・メールの受信・リッチテキスト・WebSocket の機能が無い。取り込みのファイルも Active Storage に置かない（`implementation-plan.md` M29） |
| image_processing の gem と、`Dockerfile` の libvips | 外した | Active Storage の画像の変換にだけ使う |
| kamal の gem と、`.dockerignore` の `/.kamal` | 外した | Kamal でデプロイしない。デプロイ先の選び方は [decisions.md「8. 実行基盤とデータ基盤：PostgreSQL と Solid 系で始め、デプロイ先は運用人員で選ぶ」](../architecture/decisions.md#8-実行基盤とデータ基盤postgresql-と-solid-系で始めデプロイ先は運用人員で選ぶ) にある |
| Action Mailer | 残した | 通知のメールを送る（[ADR 007](../adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md)） |
| thruster の gem | 残した | `Dockerfile` の起動の命令が `bin/thrust` で Puma を包む |

外した部品の定数が起動の後に無く、Action Mailer があることは `spec/platform/framework_loading_spec.rb` が確かめる。部品を足すときは、この表と spec を同じ変更で直す。

次のファイルは、Rails が生成したまま残っている。

- **`credentials.yml.enc`**：暗号化した秘密情報。復号の鍵 `config/master.key` は `.gitignore` で除外していて、リポジトリに無い。アプリのコードが読むのは、本番の SendGrid の API キーと Webhook の署名の公開鍵（`sendgrid.api_key`・`sendgrid.webhook_public_key`。`environments/production.rb`）だけで、本番の `secret_key_base`（セッションの Cookie の暗号化に使う）も Rails がここから取る。本番のコンテナには `RAILS_MASTER_KEY` を渡す（`Dockerfile` の冒頭のコメント）。開発とテストでは、Rails が `tmp/local_secret.txt` を作って使う。
- **`locales/en.yml`**：翻訳の見本の 1 行だけがある。本デモの機能は使っていない。
