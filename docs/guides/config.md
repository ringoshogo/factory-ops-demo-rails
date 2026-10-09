# config/ の設定ファイル

`config/` には、Rails が起動するときに読む設定と、DB・ジョブ・CI などの道具が読む設定が並ぶ。多くは `rails new` が生成したままで、本デモが手を入れたのは一部である。この文書は、まず全ファイルの一覧で生成のままか変えたかを示し、次に変えたものを目的ごとに、何を変えたかとその理由を説明する。

## 一覧

「出自」の「生成のまま」は `rails new` が作った内容から変えていないもの、「変更」は生成されたファイルに手を入れたもの、「追加」は本デモで足したファイルである。

| ファイル | 役割 | 出自 | 説明する節 |
|---|---|---|---|
| `boot.rb` | Bundler と bootsnap を読み込む。起動の最初に読まれる | 生成のまま | — |
| `application.rb` | アプリ全体の設定 | 変更 | [起動とリクエスト](#起動とリクエスト)・[DB の接続](#db-の接続)・[ジョブ](#ジョブ) |
| `environment.rb` | `application.rb` を読み込み、アプリを初期化する | 生成のまま | — |
| `environments/development.rb`・`test.rb`・`production.rb` | 環境ごとの設定 | 生成のまま | [環境ごとの設定](#環境ごとの設定) |
| `initializers/cors.rb` | CORS の設定。全行がコメント | 生成のまま | [起動とリクエスト](#起動とリクエスト) |
| `initializers/filter_parameter_logging.rb` | ログに出さないパラメータ | 生成のまま | — |
| `initializers/inflections.rb` | 単数形・複数形の規則。全行がコメント | 生成のまま | — |
| `initializers/strong_migrations.rb` | 危険なマイグレーションを止める gem の設定 | 追加 | [DB の接続](#db-の接続) |
| `initializers/tenancy.rb` | 接続を貸し出すたびにテナントの設定を空にする | 追加 | [DB の接続](#db-の接続) |
| `routes.rb` | URL とコントローラの対応 | 変更 | [起動とリクエスト](#起動とリクエスト) |
| `puma.rb` | Web サーバー Puma の設定 | 生成のまま | — |
| `database.yml` | DB の接続先とロール | 変更 | [DB の接続](#db-の接続) |
| `queue.yml` | Solid Queue のワーカーの設定 | 追加（生成器のまま） | [ジョブ](#ジョブ) |
| `recurring.yml` | Solid Queue の定期実行 | 追加（生成器のまま） | [ジョブ](#ジョブ) |
| `ci.rb` | `bin/ci` が流す工程 | 変更 | [CI の工程](#ci-の工程) |
| `bundler-audit.yml` | `bin/bundler-audit` が無視する CVE | 生成のまま | — |
| `credentials.yml.enc` | 暗号化した秘密情報 | 生成のまま | [使っていない機能の設定](#使っていない機能の設定) |
| `cable.yml` | Action Cable の接続先 | 生成のまま | [使っていない機能の設定](#使っていない機能の設定) |
| `storage.yml` | Active Storage の保存先 | 生成のまま | [使っていない機能の設定](#使っていない機能の設定) |
| `locales/en.yml` | 翻訳の見本 | 生成のまま | [使っていない機能の設定](#使っていない機能の設定) |

Rails は、`bin/rails server` などで起動するとき、`boot.rb` → `application.rb` → `environment.rb` の順に読み、初期化の中で `environments/<環境>.rb`、`initializers/*.rb`、`routes.rb` を読む。

## 起動とリクエスト

### application.rb で変えたこと

`application.rb` は `config.api_only = true` の API モードで、生成のままの部分に次の 4 つを足した。DB とジョブに関わる 2 つは、それぞれの節で説明する。

- **`autoload_lib` の除外に `rubocop` を足す。** `lib/rubocop/` はカスタム Cop で、rubocop の gem を読み込まない本番の起動では読めない。自動読み込みの対象から外す。
- **Cookie とセッションのミドルウェアを足す。** API モードの Rails は、Cookie とセッションのミドルウェアを持たない。本デモはログインを Cookie のセッションで保つので、`ActionDispatch::Cookies` とセッションのストアを明示的に足す。セッションの Cookie は `SameSite=Lax` にし、本番では `secure` を付け、最後のリクエストから 12 時間で切れるようにする（[graphql-schema.md「1 回のリクエストがたどる道」](../architecture/graphql-schema.md#1-回のリクエストがたどる道) 1）。
- **`schema_format = :sql`**（[DB の接続](#db-の接続)）
- **`queue_adapter = :solid_queue`**（[ジョブ](#ジョブ)）

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
- 本番の `owner` は、環境変数 `DB_OWNER_USER` を渡したプロセスにだけ現れる。デプロイの担当者は、所有ロールの資格情報をマイグレーションの工程にだけ渡す（[bin.md「bin/docker-entrypoint で変えたこと」](bin.md#bindocker-entrypoint-で変えたこと)）。

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

## 環境ごとの設定

`environments/` の 3 ファイルは生成のままである。本デモの読み方で知っておくとよいのは次の 2 つ。

- **`test.rb` の `eager_load = ENV["CI"].present?`**：CI ではテストの前に全コードを読み込む。`packs/*/app/` のファイル名と定数名が合わないなど、自動読み込みの誤りは CI で落ちる。
- **`production.rb` に Solid Queue の `connects_to` が無い**：[ジョブ](#ジョブ) のとおり、意図して書いていない。

## CI の工程

`ci.rb` は、`bin/ci` が順に流す工程を `step` で並べる。生成のままの工程から、次のように変えた。

| 工程 | 生成のまま | 本デモ | 理由 |
|---|---|---|---|
| Packages: packwerk | — | `bin/packwerk validate && bin/packwerk check` | 依存の向きと公開 API の限定を強制する（[ADR 002](../adr/002-packwerkを初日からCIで強制する.md)） |
| Tests | `bin/rails test` | `bin/rails db:test:prepare && bundle exec rspec` | テストに RSpec を使う |
| Schema | — | `bin/check-structure` | `structure.sql` の往復を確かめる（[ADR 001](../adr/001-スキーマ管理にridgepoleを採用しない.md)） |

GitHub Actions は `bin/ci` を呼ばず、同じ検査を `.github/workflows/ci.yml` から直接流す（[bin.md「CI が使うもの」](bin.md#ci-が使うもの)）。

## 使っていない機能の設定

次のファイルは、Rails が生成したまま残っているが、本デモの機能は使っていない。

- **`credentials.yml.enc`**：暗号化した秘密情報。復号の鍵 `config/master.key` は `.gitignore` で除外していて、リポジトリに無い。アプリのコードは credentials を読まないが、本番の `secret_key_base`（セッションの Cookie の暗号化に使う）はここから取る。本番のコンテナには `RAILS_MASTER_KEY` を渡す（`Dockerfile` の冒頭のコメント）。開発とテストでは、Rails が `tmp/local_secret.txt` を作って使う。
- **`cable.yml`**：Action Cable（WebSocket）の接続先。本デモに WebSocket の機能は無い。
- **`storage.yml`**：Active Storage（ファイルの添付）の保存先。本デモにファイルの添付は無い。
- **`locales/en.yml`**：翻訳の見本の 1 行だけがある。
