# config/ の設定ファイル

`config/` には、Rails が起動するときに読む設定と、DB・ジョブ・CI などの道具が読む設定が並ぶ。多くは `rails new` が生成したままで、本デモが手を入れたのは一部である。この文書は、まず全ファイルの一覧で生成のままか変えたかを示し、次に変えたものを目的ごとに、何を変えたかとその理由を説明する。

## 一覧

「出自」の「生成のまま」は `rails new` が作った内容から変えていないもの、「変更」は生成されたファイルに手を入れたもの、「追加」は本デモで足したファイルである。

| ファイル | 役割 | 出自 | 説明する節 |
|---|---|---|---|
| `boot.rb` | Bundler と bootsnap を読み込む。起動の最初に読まれる | 生成のまま | — |
| `application.rb` | アプリ全体の設定 | 変更 | [起動とリクエスト](#起動とリクエスト)・[DB の接続](#db-の接続)・[ジョブ](#ジョブ)・[ログ](#ログ) |
| `environment.rb` | `application.rb` を読み込み、アプリを初期化する | 生成のまま | — |
| `environments/development.rb`・`test.rb`・`production.rb` | 環境ごとの設定 | 変更 | [環境ごとの設定](#環境ごとの設定)・[ログ](#ログ) |
| `initializers/cors.rb` | CORS の設定。全行がコメント | 生成のまま | [起動とリクエスト](#起動とリクエスト) |
| `initializers/event_log.rb` | `Rails.event` のイベントを 1 行の JSON で書く購読者を登録する | 追加 | [ログ](#ログ) |
| `initializers/filter_parameter_logging.rb` | ログに出さないパラメータ | 生成のまま | [ログ](#ログ) |
| `initializers/inflections.rb` | 単数形・複数形の規則。全行がコメント | 生成のまま | — |
| `initializers/strong_migrations.rb` | 危険なマイグレーションを止める gem の設定 | 追加 | [DB の接続](#db-の接続) |
| `initializers/tenancy.rb` | 接続を貸し出すたびにテナントの設定を空にする | 追加 | [DB の接続](#db-の接続) |
| `routes.rb` | URL とコントローラの対応 | 変更 | [起動とリクエスト](#起動とリクエスト) |
| `puma.rb` | Web サーバー Puma の設定 | 生成のまま | — |
| `database.yml` | DB の接続先とロール | 変更 | [DB の接続](#db-の接続) |
| `queue.yml` | Solid Queue のワーカーの設定 | 追加（生成器のまま） | [ジョブ](#ジョブ) |
| `recurring.yml` | Solid Queue の定期実行 | 追加（生成器のまま） | [ジョブ](#ジョブ) |
| `test_layers.yml` | テストの層ごとの置き場と、割合の目安。`bin/test-layers` が読む | 追加 | [testing.md「テストの層」](testing.md#テストの層) |
| `ci.rb` | `bin/ci` が流す工程 | 変更 | [CI の工程](#ci-の工程) |
| `bundler-audit.yml` | `bin/bundler-audit` が無視する CVE | 生成のまま | — |
| `credentials.yml.enc` | 暗号化した秘密情報 | 生成のまま | [使っていない機能の設定](#使っていない機能の設定) |
| `locales/en.yml` | 翻訳の見本 | 生成のまま | [使っていない機能の設定](#使っていない機能の設定) |

Rails は、`bin/rails server` などで起動するとき、`boot.rb` → `application.rb` → `environment.rb` の順に読み、初期化の中で `environments/<環境>.rb`、`initializers/*.rb`、`routes.rb` を読む。

## 起動とリクエスト

### application.rb で変えたこと

`application.rb` は `config.api_only = true` の API モードで、生成のままの部分から使わない部品の読み込みを外し、次の 5 つを足した。DB・ジョブ・ログに関わる 3 つは、それぞれの節で説明する。外した部品は [使っていない機能の設定](#使っていない機能の設定) で説明する。

- **`autoload_lib` の除外に `rubocop` と `schema_compat.rb` を足す。** `lib/rubocop/` はカスタム Cop で、`lib/schema_compat.rb` はスキーマの互換の判定である。どちらも開発とテストのグループにしかない gem（rubocop・graphql-schema_comparator）を読むので、本番の起動では読めない。自動読み込みの対象から外す。
- **Cookie とセッションのミドルウェアを足す。** API モードの Rails は、Cookie とセッションのミドルウェアを持たない。本デモはログインを Cookie のセッションで保つので、`ActionDispatch::Cookies` とセッションのストアを明示的に足す。セッションの Cookie は `SameSite=Lax` にし、本番では `secure` を付け、最後のリクエストから 12 時間で切れるようにする（[graphql-schema.md「1 回のリクエストがたどる道」](../architecture/graphql-schema.md#1-回のリクエストがたどる道) 1）。
- **`schema_format = :sql`**（[DB の接続](#db-の接続)）
- **`queue_adapter = :solid_queue`**（[ジョブ](#ジョブ)）
- **`Platform::RequestContext` のミドルウェア**（[ログ](#ログ)）

### CSRF を防ぐ前提：CORS を開けない

API モードは CSRF 対策（フォームのトークン）を持たない。本デモは、次の 3 つの組み合わせで他サイトからの書き込みを防ぐ。

1. セッションの Cookie を `SameSite=Lax` にし、他サイトからの POST に Cookie を付けさせない（`application.rb`）。
2. `ApplicationController` が、本文が `application/json` でないリクエストを 415 で拒む。他サイトのフォームは `application/json` を送れない。
3. CORS を開けない。`initializers/cors.rb` は生成のまま全行がコメントで、`rack-cors` も Gemfile でコメントのままである。他サイトの JavaScript が `fetch` で `application/json` を送るには CORS のプリフライトが要り、それが通らない。

フロントエンドを別のオリジンから呼ぶことになったら、`cors.rb` を有効にする前に、この前提を見直す。

### routes.rb で足したもの

生成のままの `GET /up`（死活監視）に、次の 2 つを足した。

- `resource :session, only: %i[create destroy]`：ログインとログアウト（`SessionsController`）。GraphQL に認証の mutation は置かない
- `post "graphql"`：GraphQL の入口（`GraphqlController`）。POST だけを受け付ける

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

開発とテストの接続先は、`compose.yaml` の PostgreSQL 18（ポート 5433）である。主キーに使う `uuidv7()` は 18 から入った関数である（[ADR 003](../adr/003-主キーにUUIDv7を使う.md)）。

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
- **`queue.yml`・`recurring.yml`**：`solid_queue:install` が作ったまま。`queue.yml` は dispatcher と worker の数とポーリングの間隔、`recurring.yml` は本番で毎時、終わったジョブの行を消すタスクを定める。どちらも `bin/jobs` が読む。

ジョブを登録する時機（コミットの後か、トランザクションの中か）は設定ではなく、`ApplicationJob`（`packs/platform`）と `Contracts::EventJob`（`packs/contracts`）の `enqueue_after_transaction_commit` で決める。

## ログ

本デモのログは、1 行が 1 件の JSON で、どの要求・テナント・ユーザー・GraphQL の操作・ジョブ・イベントのものかを `context` に持つ。運用者は、相関 ID（`correlation_id`）で、発注側の発注から受注側の受注確定までのように、テナントをまたぐ一連の処理を引ける。個人情報と秘密は書かない。

### ログの出口：Rails.event と Rails.logger

ログの出口は 2 つある。

- **`Rails.event`**：Rails 8.1 は、コントローラ・ジョブの計装を構造化イベント（`action_controller.request_started`・`active_job.completed` など）として `Rails.event` に出す。イベントをログに書く購読者は付属しないので、`initializers/event_log.rb` が `Platform::JsonLogSubscriber`（`packs/platform/lib/platform/`）を登録する。購読者は 1 件のイベントを `name`・`payload`・`tags`・`context`・`timestamp` の 1 行にし、本番では標準出力に、開発とテストでは `log/events.log` に書く。
- **`Rails.logger`**：本番とテストでは、`Platform::JsonLogFormatter` を付けたロガーにし、残る文字列の行も JSON にして、同じ文脈を `context` に入れる。ロガーは `ActiveSupport::TaggedLogging` で包まない。TaggedLogging はタグを文字列としてメッセージに混ぜてから書式に渡すので、要求 ID などはタグにせず、文脈から `context` の項目に入れる。

### イベントごとに書く項目

Rails の構造化イベントは、要求の引数・ジョブの引数・例外のメッセージを載せる。`filter_parameter_logging.rb` の `filter_parameters` は名前で値を隠すだけで、GraphQL の `query` と `variables` の中身や自由記述を覆わない。そこで購読者は、イベントの名前ごとに書く項目を次の表で決め、表に無い項目を落とす。

| イベント | 書く項目 | 書かないもの |
|---|---|---|
| `action_controller.request_started` | `controller`・`action`・`format` | `params`。`GraphqlController` の要求は、`operation_name`、`query` の SHA-256 の要約（`query_sha256`）、`variables` のキーの一覧（`variable_keys`）に置き換える。操作名と変数のキーは利用者が送る値なので、GraphQL の名前の形（`/\A[_A-Za-z][_0-9A-Za-z]*\z/`）の文字列だけを書き、ハッシュ・配列などは中の値ごと落とす |
| `action_controller.request_completed` | `controller`・`action`・`status`・`duration_ms` などの数値 | — |
| `action_controller.rescue_from_handled` | `exception_class` | 例外のメッセージとバックトレース。メッセージは DB のエラーの詳細などに入力の値を含む |
| `active_job.enqueued`・`enqueued_at`・`started`・`completed`・`retry_scheduled`・`retry_stopped`・`discarded` | `job_class`・`job_id`・`queue`・時間・`exception_class` | ジョブの引数と、例外のメッセージとバックトレース。`ApplicationJob.log_arguments = false` にし、購読者も落とす |
| `graphql.operation_completed`（アプリが出す） | `operation_name`・`result`（`success`・`user_error`・`error`）・`user_error_codes`・`duration_ms` | — |
| `contracts.event_handled`（アプリが出す） | `event_name`・`receiver`・`delivery_lag_ms`（受け手の始まりの時刻 − 発行時刻） | — |
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
- **付帯情報**：`ApplicationJob` は、ジョブを作った時点（`initialize`）の相関 ID とテナント ID を付帯情報に入れる。`Contracts.publish` は、ジョブを作った後、登録の前に、付帯情報をイベントのもの（[data-model.md「イベントの受け口と冪等キー」](../architecture/data-model.md#イベントの受け口と冪等キー)）に置き換える。付帯情報は直列化の最上位の項目（`"app_metadata"`）に入るので、再試行の登録にも引き継がれる（[ADR 005](../adr/005-イベントのジョブをトランザクション内で登録する.md) 決定 3）。項目の無いジョブは、付帯情報の文脈を設定せずに動かす。

受け手の中で発行するイベントは、同じ相関 ID と、因果 ID として受け手が受け取ったイベントの `event_id` を持つ。これで、発注側の `placePurchaseOrder` の要求 → 「発注登録」 → 受注側の ACL → 「受注確定」 → 購買の受け手、の全ログが同じ相関 ID を持つ（`spec/contracts/correlation_spec.rb`）。テナントは途中で変わるので、相関 ID でログを引けるのは運用者だけで、テナントの利用者には相手側のログを見せない。

開発の環境で、2 社のイベントの配送が同じ相関 ID で並ぶことは、`bin/dev` と `bin/jobs` を動かして発注を 1 件登録し、次で確かめる。

```sh
grep <相関 ID> log/events.log
```

## 環境ごとの設定

`environments/` の 3 ファイルは、ログの書式（[ログ](#ログ)）と、N+1 の検出（Bullet。[graphql-schema.md「ページングと N+1」](../architecture/graphql-schema.md#ページングと-n1)）を足したほかは生成のままである。本デモの読み方で知っておくとよいのは次の 2 つ。

- **`test.rb` の `eager_load = ENV["CI"].present?`**：CI ではテストの前に全コードを読み込む。`packs/*/app/` のファイル名と定数名が合わないなど、自動読み込みの誤りは CI で落ちる。
- **`production.rb` に Solid Queue の `connects_to` が無い**：[ジョブ](#ジョブ) のとおり、意図して書いていない。

## CI の工程

`ci.rb` は、`bin/ci` が順に流す工程を `step` で並べる。生成のままの工程から、次のように変えた。

| 工程 | 生成のまま | 本デモ | 理由 |
|---|---|---|---|
| Packages: packwerk | — | `bin/packwerk validate && bin/packwerk check` | 依存の向きと公開 API の限定を強制する（[ADR 002](../adr/002-packwerkを初日からCIで強制する.md)） |
| Ledgers | — | `bin/check-open-items` | 残件と改善の候補の台帳の形と、ID の参照を確かめる（[dev-cycle.md「機械で守ること」](dev-cycle.md#機械で守ること)） |
| Ledgers: commit references | — | `bin/check-commit-refs` | 台帳・証跡・引き継ぎに書いた SHA が HEAD の祖先かを確かめる（[dev-cycle.md「機械で守ること」](dev-cycle.md#機械で守ること)） |
| GraphQL: schema compatibility | — | `bin/check-schema-compat` | `origin/main` との分岐点からの、非推奨を経ない破壊的変更を止める（[graphql-schema.md「互換の判定」](../architecture/graphql-schema.md#互換の判定)） |
| Tests | `bin/rails test` | `bin/rails db:test:prepare && bundle exec rspec --format progress --format json --out tmp/rspec.json` | テストに RSpec を使う。層ごとの件数を数えるため、JSON の出力も書く |
| Tests: layers | — | `bin/test-layers tmp/rspec.json` | テストの層ごとの件数・割合・時間を報告し、未分類のファイルを止める（[testing.md「テストの層」](testing.md#テストの層)） |
| Schema | — | `bin/check-structure` | `structure.sql` の往復を確かめる（[ADR 001](../adr/001-スキーマ管理にridgepoleを採用しない.md)） |

GitHub Actions は `bin/ci` を呼ばず、同じ検査を `.github/workflows/ci.yml` から直接流す（[bin.md「CI が使うもの」](bin.md#ci-が使うもの)）。

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

次のファイルは、Rails が生成したまま残っているが、本デモの機能は使っていない。

- **`credentials.yml.enc`**：暗号化した秘密情報。復号の鍵 `config/master.key` は `.gitignore` で除外していて、リポジトリに無い。アプリのコードは credentials を読まないが、本番の `secret_key_base`（セッションの Cookie の暗号化に使う）はここから取る。本番のコンテナには `RAILS_MASTER_KEY` を渡す（`Dockerfile` の冒頭のコメント）。開発とテストでは、Rails が `tmp/local_secret.txt` を作って使う。
- **`locales/en.yml`**：翻訳の見本の 1 行だけがある。
