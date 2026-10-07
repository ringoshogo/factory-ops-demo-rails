# 実装計画

設計文書（`architecture/`・`adr/`）を、動くアプリに落とす順番を定める。実装を担当するエージェントは、マイルストーンを M1 から 1 つずつ実装する。1 つのマイルストーンは 1 回の作業で終わる大きさ（数百行）にしてある。

## 1 つのマイルストーンの進め方

担当者は、マイルストーンに着手するたびに次の順で進める。

1. 本書の該当節を読み、「実装する文書の節」に挙げた設計文書の節を読む。
2. 「作るもの」を実装する。設計文書に書いていないことを決めたら、「文書に残すこと」に挙げた文書へ、同じ作業の中で書き足す。設計文書と食い違う実装にしたときも、先に文書を直す。
3. 「完了条件」と「共通の完了条件」をすべて通す。1 つでも落ちていれば、次のマイルストーンへ進まない。
4. `handoff.md` の「リポジトリの状態」に、終えたマイルストーンを書く。

設計文書の規則を守る仕組みは、テスト・packwerk・基底クラス・DB の制約のどれかで作る。規則をコメントや README にだけ書いて終えない。

### 共通の完了条件

M2 以降のすべてのマイルストーンで、次のコマンドが成功する。CI（M1 で作る）も同じものを実行する。

```sh
bin/rubocop
bin/packwerk validate && bin/packwerk check   # M2 から
bundle exec rspec
bin/rails db:migrate && git diff --exit-code db/structure.sql
```

packwerk の違反は `package_todo.yml` に逃がさず、その場で直す（`adr/002`）。

## 環境

次の値は決まっている。担当者は変えない。

| 項目 | 値 |
|---|---|
| Ruby | 3.3.3（rbenv）。3.3.0 は構文解析の不具合（Ruby bug #20090）で Rails 8.1 の Action View を読み込めない |
| Rails | 8.1 系、API モード |
| DB | PostgreSQL 18（`docker compose` の `postgres:18`）。開発とテストの両方で使う |
| pg_dump | 18 系。手元は Homebrew の `libpq`（keg-only）を PATH の先頭に足して使い、CI は PGDG の `postgresql-client-18` を入れる |
| GraphQL | graphql-ruby、Action Policy（`action_policy-graphql`） |
| ジョブ | Solid Queue を業務 DB と同じ DB・同じ接続に置く（`adr/005`） |
| パッケージ | packs-rails、packwerk、packwerk-extensions（`adr/002`） |
| スキーマ | Rails マイグレーション＋`db/structure.sql`、strong_migrations（`adr/001`） |
| テスト | RSpec（rspec-rails）＋FactoryBot |
| 静的解析 | rubocop-rails-omakase を起点にする（`decisions.md` 7 章） |

手元には PostgreSQL 16 が入っている。`uuidv7()` は 18 にしか無いので、DB は必ずコンテナの 18 を使う。

## マイルストーンの一覧

骨組み（M1〜M7）を先に作り、業務機能（M8〜M19）は業務の流れの順に、薄い縦切りで足す。業務機能の各マイルストーンは、テーブル・公開 API・policy・イベント・GraphQL のフィールド・行列テストの行を 1 つの単位で作る。

| | マイルストーン | 機械で守るようになる規則 |
|---|---|---|
| M1 | 骨組みと CI | 主キーが DB の `uuidv7()` で作られ、`structure.sql` に残る |
| M2 | パッケージ構成と packwerk | 許可した向きにしか依存できず、公開 API 以外を参照できない |
| M3 | テナントの強制（DB 側） | テナント未設定では例外か 0 行になり、相手名義では書けない |
| M4 | リクエストの入口 | GraphQL の実行全体が 1 つのトランザクションと `SET LOCAL` の中で動く |
| M5 | GraphQL の基盤 | 宣言の無い型・リゾルバ・mutation は拒否され、相手側の型へたどれない |
| M6 | 行列テストの枠 | すべての表と入口が、テナントの種類ごとの期待値を持つ |
| M7 | イベントの登録と受信 | イベントは業務データと同じトランザクションで登録され、受け手は冪等に動く |
| M8 | 取引関係と権限付与 | 経路 2 が有効な取引関係でだけ開き、失効で閉じる |
| M9 | カタログ | 経路 1 が `view_catalog` の付与でだけ開く |
| M10 | 発注登録と受注の連結 | 発注と受注がイベントだけで連結し、同じイベントで受注が 2 件できない |
| M11 | 品番の対応表と照合のやり直し | 照合できない明細を持つ受注が確定しない |
| M12 | 在庫と引当 | 有効在庫が負にならず、在庫の変更が必ず移動履歴を残す |
| M13 | 出荷指示と出荷実績の計上 | 出荷が `active` の引当だけを消費する |
| M14 | 出荷計上の還流と経路 3 | 経路 3 が `view_shipments` の付与と自社の発注でだけ開く |
| M15 | 取消依頼と審査 | 審査中は出荷が止まり、取消は受注側の承認でだけ成立する |
| M16 | 受注側の取消と、取消と出荷の競合 | 同時に進んだ取消と出荷のどちらか一方だけが成立する |
| M17 | 検収 | 検収数量が出荷数量を超えず、検収が受注側へ 1 回だけ届く |
| M18 | 請求の締め | 締めが取引先ごとに直列になり、税が請求書・税率ごとに 1 回だけ丸められる |
| M19 | 請求書の発行と受領請求書 | 確定した請求書が変わらず、写しが発注側に 1 回だけ届く |
| M20 | ダッシュボードと失効の通し試験 | 失効の後も連結済みの取引が請求まで進む |
| M21 | シードデータ | — |
| M22 | フロントエンド | 当面は範囲外 |

`handoff.md` は骨組みを「パッケージ構成 → テナントの強制 → 行列テスト → イベント」の 4 つにしていた。本書はこれに 2 つ足した。1 つは M1（`rails new`・DB・CI）で、他のすべての前提になる。もう 1 つは M5（GraphQL の基盤）で、行列テストの「入口」の軸が GraphQL のフィールドなので、行列テストの枠より先に要る。テナントの強制は、DB の仕組み（M3）とリクエストの入口（M4）に分けた。1 回の作業に収めるためである。

---

## M1 骨組みと CI

**目的**：アプリの雛形と DB を用意し、主キーが `DEFAULT uuidv7()` のまま `structure.sql` に保たれることを確かめる（`adr/003` の未確認の事項）。

**作るもの**

- `rails new . --api -d postgresql -T --skip-solid --skip`
  - `-T` で minitest を外し、rspec-rails を入れる。RSpec を選ぶのは、設計文書がガードテストを `spec/` のパスで定めているからである。
  - `--skip-solid` で Solid Queue・Cache・Cable の別 DB の雛形を作らせない。Solid Queue は M7 で、業務 DB と同じ DB に入れる。
  - `--skip` で既存の `README.md` と `docs/` を上書きさせない。
- `compose.yaml`：`postgres:18`。手元の PostgreSQL 16 と衝突しないよう、ホスト側のポートを 5433 にする。PostgreSQL 18 のイメージはデータの置き場が変わったので、ボリュームは `/var/lib/postgresql` に付ける。
- `config/database.yml`：コンテナの DB を指す。DB ロールは M3 で分けるので、M1 はコンテナの既定のロールでよい。
- `config.active_record.schema_format = :sql`。
- 最初のマイグレーションで `tenants` を作る（`id uuid DEFAULT uuidv7()`・`code`・`name`・`partner_code`）。`tenants` は RLS を付けない表なので、テナントの強制より先に作れる。
- strong_migrations。`execute` を使うマイグレーションは `safety_assured` で包む。
- `spec/db/uuidv7_default_spec.rb`：`tenants.id` の列の既定値が `uuidv7()` であることと、作った行の `uuid_extract_version(id)` が 7 であることを確かめる。
- `.github/workflows/ci.yml`：`postgres:18` のサービスを立て、PGDG の apt から `postgresql-client-18` を入れる。rubocop・packwerk（M2 で有効にする）・`db:test:prepare`・rspec・`structure.sql` の差分検査を実行する。
- `bin/setup` を、コンテナの起動と `db:prepare` まで行う形に直す。

手元の pg_dump も 18 系にする（Homebrew の `libpq` か `postgresql@18`）。16 系の pg_dump は 18 のサーバーに対して動かず、`structure.sql` を書けない。

**完了条件**

```sh
docker compose up -d
bin/rails db:drop db:create db:migrate
grep -q "DEFAULT uuidv7()" db/structure.sql
bin/rails db:drop db:create db:schema:load && bin/rails db:schema:dump && git diff --exit-code db/structure.sql
bundle exec rspec spec/db/uuidv7_default_spec.rb
bin/rubocop
```

CI のワークフローは、GitHub のリポジトリを作った後の最初の push で通ることを確かめる（`handoff.md`「次にやること」2）。それまでは、ワークフローの各ステップのコマンドを手元で通す。

**実装する文書の節**：`adr/001` の決定 1・3・6、`adr/003` の決定、`data-model.md`「テナントの持ち方」の主キー

**文書に残すこと**：`adr/003` の未確認の事項を、確かめた結果で置き換える。`DEFAULT uuidv7()` が保たれなければ、`adr/003`「見直す条件」の退路（アプリで `SecureRandom.uuid_v7`）に切り替え、ADR を改める。

## M2 パッケージ構成と packwerk

**目的**：`context-map.md`「許可する依存の向き」を packwerk の依存チェックで、公開 API の限定をプライバシーチェックで、CI が強制する。

**作るもの**

- packs-rails・packwerk・packwerk-extensions。`packwerk.yml` で privacy のチェッカーを有効にする。
- `packs/` の下に 8 つのパッケージを作る。各 `package.yml` は `enforce_dependencies: strict`、コンテキストと `contracts` は `enforce_privacy: strict`（公開は `app/public/`）にする。

| パッケージ | 依存してよい先 |
|---|---|
| `platform` | なし |
| `contracts` | `platform` |
| `partnerships` | `platform` |
| `inventory` | `platform`、`partnerships` |
| `billing` | `platform`、`partnerships`、`contracts` |
| `fulfillment` | `platform`、`partnerships`、`contracts`、`inventory` |
| `sales` | `platform`、`partnerships`、`contracts`、`inventory` |
| `purchasing` | `platform`、`partnerships`、`contracts`、`sales` |
| ルートパッケージ | すべて |

- `packs/platform` は新しく足すパッケージで、Rails の基底クラス（`ApplicationRecord`・`ApplicationJob`）と、テナントの仕組み（M3 の `Current`・`Tenancy`）を置く。どのコンテキストにも属さず、プライバシーチェックを掛けない。
  - 基底クラスをルートパッケージに置けない理由：各パッケージのモデルは `ApplicationRecord` を参照する。ルートパッケージはすべてに依存するので、パッケージからルートへの依存を宣言すると循環になり、`packwerk validate` が落ちる。
- `purchasing` から `sales` への依存は、`sales` の公開 API のうち `Sales::PublishedCatalog` だけを使う。packwerk は公開 API の中の個別のクラスを区別しないので、`spec/packwerk/purchasing_uses_only_published_catalog_spec.rb` が `packs/purchasing` の中の `Sales::` の参照を走査し、`Sales::PublishedCatalog` 以外があれば落とす。
- `.rspec` と `spec/spec_helper.rb` を、`packs/*/spec` のテストも走らせる形にする。
- `spec/packwerk/enforcement_spec.rb`：一時ファイルで違反を作り、`bin/packwerk check <ファイル>` が失敗することを確かめる。違反は 2 種類作る。`purchasing` から `Inventory::` を参照する依存違反と、`sales` から `Inventory` の公開 API でないクラスを参照するプライバシー違反である。

packs-rails が Rails 8.1 で動かない場合は、packs-rails を外し、`config/application.rb` で `packs/*/app/*` を自動読み込みと eager load の対象に足す。packs-rails が行うのはこの設定なので、packwerk の構成は変わらない。

**完了条件**

```sh
bin/packwerk validate
bin/packwerk check
bundle exec rspec spec/packwerk
bin/rails runner 'Rails.autoloaders.main.eager_load; puts :ok'   # packs の自動読み込み
```

**実装する文書の節**：`adr/002` の決定、`context-map.md`「疎結合を守る規則」1・2・5

**文書に残すこと**：`context-map.md`「許可する依存の向き」の表に `platform` を足し、`contracts` の依存先を「`platform` だけ」に直す（コンテキストに属さないパッケージの表にも足す）。`adr/002` の未確認の事項を、確かめた結果で置き換える。packs-rails を外した場合は、その手順を `adr/002` に書く。

## M3 テナントの強制（DB 側）

**目的**：テナントを設定せずにテナントの表を引くと、アプリでは例外、生 SQL では 0 行になる。相手テナントの名義では、どの表にも書けない。テナントの表を足すときに RLS を付け忘れられない。

**作るもの**

- DB ロールを 2 つに分ける。`docker compose` の初期化スクリプトで作る。
  - **所有ロール**（例：`factory_owner`）：表の所有者で、マイグレーションと `structure.sql` の読み込みを行う。`BYPASSRLS` を持つ。認証専用の関数（M4）は、このロールの `SECURITY DEFINER` で RLS の外で動かす。`FORCE ROW LEVEL SECURITY` の表は所有者にも RLS が掛かるので、`BYPASSRLS` が無いと関数が行を引けない。
  - **アプリのロール**（例：`factory_app`）：表の所有者でも `BYPASSRLS` でもない。アプリ・テスト・ワーカーはすべてこのロールで接続する（`adr/001` 決定 5）。
- アプリのロールへの権限は、`db:migrate`・`db:schema:load`・`db:test:load_schema` の後に走る rake タスクで付与する。Rails の pg_dump は `-x` で権限を落とすので、権限を `structure.sql` に載せても、テスト DB には再現されない。
- `database.yml`：接続はアプリのロール、DB のタスクは所有ロールで行う。同じ DB に 2 つの設定を置き、タスク用の設定だけ `database_tasks: true` にする形を第一候補にする。
- マイグレーションの補助（`lib/tenant_table.rb` など）：`create_tenant_table :name` が次をまとめて作る。テナントの表は必ずこれで作る。
  - `id uuid DEFAULT uuidv7()`、`owner_tenant_id uuid NOT NULL`、`UNIQUE (owner_tenant_id, id)`
  - `ENABLE`・`FORCE ROW LEVEL SECURITY` と `owner_write` のポリシー（`data-model.md`「RLS」）
  - `down` で逆の操作
  - 親子の複合外部キーを張る `add_tenant_reference`、読む経路のポリシーを足す `add_partner_read_policy`
- `current_tenant_id()` 関数のマイグレーションと、`users`（`partnerships` の表）を補助で作る。
- `packs/platform`：
  - `Current`（`tenant_id`・`actor`）
  - `Tenancy.with_tenant(tenant_id) { ... }`：トランザクションを開き、`SET LOCAL app.tenant_id` を設定し、`Current` を設定してブロックを実行する。いちばん外側のブロックを抜けるとき、`ensure` で `app.tenant_id` のセッションの値を空にする。入れ子は同じテナントだけを許し、別のテナントなら `Tenancy::TenantMismatch` を投げる（`architecture/data-model.md`「RLS」）。
  - `TenantRecord`（`ApplicationRecord` を継承した抽象クラス）：`Current.tenant_id` が空のままリレーションを作るか保存すると、`Tenancy::MissingTenant` を投げる。テナントの表のモデルはすべてこれを継承する。
- `config/initializers/tenancy.rb`：接続プールが接続を貸し出すたびに、`Tenancy.reset!` で `app.tenant_id` を空にする。
- `spec/db/tenant_columns_spec.rb`（テナント列の列挙テスト）：全 AR モデルと全表を走査し、`owner_tenant_id` を持つか、理由付きの除外宣言（`tenants`、M7 以降の `solid_queue_*`）にあることを確かめる。
- `spec/db/tenant_enforcement_spec.rb`：`owner_tenant_id` を持つ全表について、`pg_class.relforcerowsecurity` が真で、`owner_write` のポリシーがあることを `pg_policies` で確かめる。接続中のロールが所有者でも `BYPASSRLS` でもなく、`tenants` を書き換えも削除もできないことも確かめる。
- `spec/platform/tenancy_spec.rb`：未設定で `TenantRecord` を引くと例外、未設定で生 SQL を引くと 0 行、`with_tenant` を抜けた後に生 SQL が 0 行、相手名義の INSERT が拒否される、入れ子で別のテナントに切り替えると例外、を確かめる。
- `spec/platform/tenancy_session_spec.rb`：セッションの `SET` で接続に残したテナントが、`with_tenant` を抜けた後にも、次に貸し出した接続にも残らないことを確かめる。

**完了条件**

```sh
bin/rails db:drop db:create db:migrate db:test:prepare
bundle exec rspec spec/db spec/platform
```

**実装する文書の節**：`data-model.md`「テナントの持ち方」「RLS」、`decisions.md` 2 章（完全分離型の防壁の表と相互アクセス型）、`adr/001` 決定 2・5

**文書に残すこと**：DB ロールの分け方と、権限を rake タスクで付与することを `data-model.md`「RLS」に書く。ロールの名前を決めたら同じ節に書く。

## M4 リクエストの入口

**目的**：ログインは RLS の外の関数 1 つだけを通り、GraphQL の実行はすべてテナントを設定したトランザクションの中で動く。

**作るもの**

- `users.password_digest` と bcrypt（`has_secure_password`）。`data-model.md` の `users` に足す。
- 認証専用の関数：メールアドレスから、ユーザー ID・所有テナント・`password_digest` だけを返す。所有ロールの `SECURITY DEFINER` にする。
- `SessionsController`（ログイン・ログアウト）：関数でユーザーを引いてパスワードを照合し、ユーザー ID と所有テナント ID をセッションに保存する。関数の呼び出しと照合は `partnerships` の公開 API `Partnerships::Authentication` に置き、操作者は `Partnerships::Actor`（ユーザー ID・所有テナント・名前・メールアドレス・役割の値）で渡す。M8 は、この `Actor` を広げる。
- API モードに Cookie とセッションのミドルウェアを足し、Cookie を `SameSite=Lax` にする。
- graphql-ruby を入れ、`viewer` だけを持つスキーマを置く。
- `GraphqlController`：POST の `application/json` だけを受け付ける。`Tenancy.with_tenant` でスキーマの実行全体を包み、RLS の下でユーザーを引いて `Current.actor` に設定する。引けなければ実行せずに 401 を返す。例外ならロールバックし、それ以外はユーザーエラーを返した場合も含めてコミットする。
- `spec/requests/sessions_spec.rb`・`spec/requests/graphql_entry_spec.rb`：ログインの成否、未ログインと別テナントのセッションで 401、GET と `application/json` 以外の拒否、実行中に `current_setting('app.tenant_id')` がセッションのテナントであること、実行後に空へ戻ること。

**完了条件**

```sh
bundle exec rspec spec/requests
```

**実装する文書の節**：`graphql-schema.md`「1 回のリクエストがたどる道」1、`data-model.md`「RLS」のログインの前のユーザー検索

**文書に残すこと**：`users.password_digest` を `data-model.md` の `users` の行に、認証専用の関数が `password_digest` も返すことを同じ文書の「RLS」に書く。

## M5 GraphQL の基盤

**目的**：宣言の無い型・リゾルバ・mutation は実行時に拒否され、CI でも落ちる。発注側の視点から受注側の型へたどれない。ID から型を問わずにレコードを引く入口が無い。

**作るもの**

- `Types::BaseObject`・`Resolvers::BaseResolver`・`Mutations::BaseMutation`：`perspective` と `authorize_with` / `authorization_exempt` の宣言、宣言が無ければ開発・テストで例外、本番で拒否（`graphql-schema.md`「基底クラス」）。
- Action Policy と `action_policy-graphql`。`ApplicationPolicy` は `packs/platform` に置く。
- スキーマで `unauthorized_object`・`unauthorized_field` を上書きし、`FORBIDDEN` のトップレベルのエラーを投げる。リゾルバと mutation の `authorized?` も同じエラーを投げる。
- `object_from_id` を実装せず、呼ばれたら例外にする。`node`・`nodes` を置かない。
- `BuyerView`・`SupplierView` の空の入口、`Tenant`・`UserError`・`PageInfo`・`BigInt`。
- 公開 API の結果の値（成功なら値、失敗ならコードと入力項目）を `UserError` に写す、基底 mutation の仕組み。
- クエリの上限（`max_depth` 10、`default_page_size` 20、`default_max_page_size` 100、`max_complexity` 2,500）。
- `config.active_support.isolation_level` を `:thread` のままにし、`AsyncDataloader` を使わない。
- `spec/graphql/perspective_reachability_spec.rb`・`spec/graphql/authorization_declarations_spec.rb`：`graphql-schema.md` が定める 3 つの検査と、例外の一覧の一致。
- `spec/graphql/base_classes_spec.rb`：宣言の無い型・リゾルバ・mutation がテストの中で例外になること、`node` が無いこと、`object_from_id` が例外になること、`isolation_level` が `:thread` であること。

**完了条件**

```sh
bundle exec rspec spec/graphql
```

**実装する文書の節**：`graphql-schema.md`「視点ごとに型を分ける」「相手側の型へたどれないことの保証」「ID と `node`」「認可」「エラー」「ページングと N+1」、`adr/004`

## M6 行列テストの枠

**目的**：テナントの種類と、表・入口の組み合わせすべてに期待値がある。表や入口を足して期待値を書き忘れると、CI が落ちる。

**作るもの**

- テナントの種類（ペルソナ）を 5 つ用意する共通の世界（`spec/support/matrix_world.rb`）。

| ペルソナ | 関係 |
|---|---|
| `supplier` | 受注側 |
| `granted_buyer` | `supplier` と有効な取引関係があり、全権限の付与がある |
| `ungranted_buyer` | 有効な取引関係があり、権限付与が無い |
| `revoked_buyer` | 取引関係が失効している |
| `stranger` | 取引関係が無い |

  M8 で取引関係の表ができるまでは、`supplier` と `stranger` の 2 つで始め、M8 で残りを足す。
- **表の行列**（`spec/matrix/table_matrix_spec.rb`）：`owner_tenant_id` を持つ全表を DB から列挙し、ペルソナごとに、生 SQL で読める行の件数を所有者ごとに数え、相手名義の INSERT・相手の行への UPDATE と DELETE・自社の行を相手名義へ書き換える UPDATE を確かめる。期待値は `spec/matrix/table_expectations.rb` に全表の行を書く。既定は `OWNER_ONLY`（所有者だけが読める）で、読む経路の表（`items`・`partnerships`・`partnership_grants`・`shipments`・`shipment_lines`）だけに、読むペルソナと、見える相手の行の件数を書く。行の無い表があれば落ちる。世界の行は FactoryBot で作り、テナントの表ごとに、表の単数形の名前の factory があることも確かめる。factory は表を持つパッケージの `spec/factories` に置く（packs-rails が読み込む）。
- **入口の行列**（`spec/matrix/graphql_matrix_spec.rb`）：スキーマから `BuyerView`・`SupplierView`・`Query`（視点の入口を除く）の全フィールドと全 mutation を列挙し、ペルソナとしてログインして実行し、結果の種類（値が返る・空・`null`・`NOT_FOUND`・`NOT_PERMITTED`・`FORBIDDEN`）が `spec/matrix/graphql_expectations.rb` の期待と一致することを確かめる。期待値の無いフィールドや mutation、全ペルソナの期待が揃っていない行があれば落とす。
- 業務機能のマイルストーンは、この 2 つの期待値のファイルに行を足すだけで行列テストを増やせる。

**完了条件**

```sh
bundle exec rspec spec/matrix
```

期待値のファイルから `users` の行を消すと、表の行列が落ちることを手で確かめる。

**実装する文書の節**：`context-map.md`「テナントと所有」のデモの見せどころ、`decisions.md` 7 章（実行時のゲートと列挙テスト）

## M7 イベントの登録と受信

**目的**：イベントのジョブは業務データと同じトランザクションで登録され、ロールバックすれば消える。受け手は宛先テナントの名義で、冪等に処理する。発行元は受け手を知らない。

**作るもの**

- Solid Queue を入れ、`db/queue_schema.rb` の内容を通常のマイグレーションに写す。`queue` の DB と `connects_to` は作らない。`config.active_job.queue_adapter = :solid_queue` を `config/application.rb` に書く。`solid_queue_*` を M3 の列挙テストの除外宣言に足す。
- `ApplicationJob`（`packs/platform`）：`self.enqueue_after_transaction_commit = true`。投入時の `Current.tenant_id` を引数に載せ、実行時に `Tenancy.with_tenant` で復元する（`decisions.md` 2 章）。
- `packs/contracts`：
  - イベントの型。ID と、受け手が要る値の写しだけを持つ。ジョブの引数には、イベントの名前と、プリミティブだけのハッシュを渡す。
  - 配送表 `Contracts::Subscriptions`：イベントごとに、受け手のクラス名（文字列）と、宛先テナントを示すペイロードの項目を並べる。1 つのイベントが別のテナントの 2 つの受け手へ届く（「出荷計上」）ので、宛先は受け手ごとに書く。受け手を文字列で書くので、`contracts` は受け手のパッケージに依存しない。
  - `Contracts.publish(event)`：配送表の受け手ごとに `Contracts::EventJob` を 1 件ずつ登録する。トランザクションの外で呼ばれたら例外にする。
  - `Contracts::EventJob`（`ApplicationJob` を継承）：`self.enqueue_after_transaction_commit = false`。実行時に、宛先テナントで `Tenancy.with_tenant` を開き、受け手の `handle(event)` を呼ぶ。`limits_concurrency` を付けない。
- `spec/jobs/event_job_atomicity_spec.rb`（`adr/005` 決定 4 の 3 つ）。
- `spec/contracts/subscriptions_spec.rb`：配送表のクラス名がすべて定数として存在し、`handle` を持つこと。
- テストでのジョブの扱い：テストでも Active Job の `:test` アダプタに差し替えず、`:solid_queue` のまま `solid_queue_jobs` の行を読む。登録したイベントを受け手まで流す補助（`spec/support/events.rb` の `deliver_enqueued_events`）を作り、業務機能のテストはこれで流す。`event_job_atomicity_spec` の中で、`Contracts::EventJob.queue_adapter` が Solid Queue のアダプタであることも確かめる。
- 受け手の雛形と冪等の確かめ方：同じイベントを 2 回流しても書いた行が 1 件であることを、受け手ごとのテストに書く（`spec/support/shared_examples/idempotent_receiver.rb`）。
- カスタム Cop（`lib/rubocop/cop/factory_ops/`）：`Contracts::EventJob.perform_later` と `SolidQueue::Job` の直接呼び出しを、`Contracts.publish` の外で禁止する（`decisions.md` 5 章「投入経路を Active Job 経由に限る」）。

**完了条件**

```sh
bundle exec rspec spec/jobs spec/contracts
bin/rubocop
```

ワーカーがアプリのロールで RLS の無いキューの表を読めることを、手で確かめる。`bin/jobs` をアプリのロールで起動し、テスト用のイベントを `bin/rails runner` で登録してコミットし、受け手が行を書いたことを見る。

**実装する文書の節**：`adr/005` の決定、`data-model.md`「イベントの受け口と冪等キー」、`context-map.md`「疎結合を守る規則」3・4、`decisions.md` 5 章

**文書に残すこと**：`adr/005` の未確認の事項 3 つを、上の決定と確かめた結果で置き換える。`EventJob` の名前を `Contracts::EventJob` にしたこと、`Contracts.publish` と配送表を `adr/005` の決定 3 に書く。

---

## 業務機能のマイルストーンに共通すること

M8〜M19 の担当者は、各マイルストーンで次を作る。マイルストーンの節には、それぞれに固有のものだけを書く。

- 表は `create_tenant_table` で作り、親子は `add_tenant_reference` でつなぐ。他コンテキストへの参照は ID 列だけにする。
- 状況の導出は、`data-model.md`「状態は保存せず、時刻列から導出する」の表のとおりに公開 API で行い、表の各行に 1 つずつテストを書く。
- 公開 API は操作者を必須の引数にし、policy の `relation_scope` を掛けてから値を返す。失敗を返す操作は `transaction(requires_new: true)` の中で書き、失敗を返す前にセーブポイントまで戻す。
- イベントの受け手には、冪等の共有テスト（M7）を適用する。
- GraphQL の型・リゾルバ・mutation は M5 の基底クラスから作り、行列テストの期待値（M6）に行を足す。

## M8 取引関係と権限付与

**目的**：読む経路 2 が有効な取引関係でだけ開き、失効で閉じる。取引関係を変えるのは受注側の `admin` だけである。

**作るもの**

- `partnerships`・`partnership_grants`、`partnership_active` 関数、経路 2 の `partner_read` ポリシー
- `Partnerships::Access`・`Directory`・`Management`・`PartnershipPolicy`。`Partnerships::Actor` は M4 で作ったものに、判定に要る値を足す
- `viewer`（`partnerCode` を含む）、`supplier.partnerships`、`buyer.suppliers`（`catalog` は M9）
- `establishPartnership`・`revokePartnership`・`grantPermission`・`withdrawPermission`。最初の mutation なので、ルートの `Mutation` 型をスキーマに足し、列挙テスト（`spec/graphql/authorization_declarations_spec.rb`）の例外の一覧に `Mutation` を足す
- 行列テストのペルソナを 5 つに増やす

**完了条件**：`spec/matrix` が 5 つのペルソナで通る。`establishPartnership` が、存在しない取引用コードとテナントの `code` の指定に `NOT_FOUND` を返す。`member` の取引関係の変更が `FORBIDDEN` になる。

**実装する文書の節**：`data-model.md`「取引関係と権限付与（`partnerships`）」、`graphql-schema.md`「ID と `node`」「役割による制限」

## M9 カタログ

**目的**：読む経路 1 が、有効な取引関係と `view_catalog` の付与がある発注側にだけ、公開品目だけを見せる。

**作るもの**：`items` と経路 1 のポリシー、`Sales::Catalog`・`Sales::PublishedCatalog`、`supplier.items`・`SupplierPartnership.catalog`、`saveItem`・`setItemPublished`

**完了条件**：`spec/matrix` で、経路 1 が `granted_buyer` にだけ公開品目を返す。受注側の `supplier.items` に、他社の公開品目が混ざらない（scope が所有の条件を明示している）。`PublishedCatalogItem` が品目 ID を返さない。

**実装する文書の節**：`data-model.md`「受注（`sales`）」の `items`、`graphql-schema.md`「発注側の視点」の経路 1

## M10 発注登録と受注の連結

**目的**：発注と受注はイベントだけで連結する。同じ「発注登録」が 2 回届いても受注は 1 件である。`place_orders` の無い相手には発注できない。

**作るもの**

- `purchase_orders`・`purchase_order_lines`、`sales_orders`・`sales_order_lines`、`customer_part_mappings`（表だけ。登録は M11）
- 伝票番号の採番：テナントごとの採番行を行ロックする表を、各コンテキストに置く
- `Purchasing::Ordering.place`、発注登録・受注確定・品番照合待ちのイベントと配送表の行
- 受注側の ACL `Sales::PurchaseOrderTranslator`：対応表で照合し、受注確定か品番照合待ちを出す
- 購買の受け手：`accepted_at`・`awaiting_match_at` と明細の写し
- `placePurchaseOrder`、`buyer.purchaseOrders`・`buyer.purchaseOrder`、`supplier.salesOrders`・`supplier.salesOrder`（引当の量は M12 まで 0 とする）

**完了条件**：発注 → イベントを流す → 受注確定 → 発注が「受注済」、の通しのテスト。照合できない明細で「受注側で確認中」になるテスト。存在しない・関係の無い・失効した・付与の無い相手への発注が、どれも同じ `NOT_PERMITTED` になる。

**実装する文書の節**：`context-map.md`「発注の連結と品番の照合」1〜4、`data-model.md`「購買」「受注」「イベントの受け口と冪等キー」の該当行

**文書に残すこと**：採番の表の名前と列を `data-model.md`「テナントの持ち方」の伝票番号の項に書く。

## M11 品番の対応表と照合のやり直し

**目的**：照合できない明細を持つ受注は確定しない。対応表を登録すると、照合待ちの受注が確定まで進む。

**作るもの**：`Sales::PartMappings.register`（照合待ちの受注を照合し直す）、`supplier.partMappings`、`registerPartMapping`

**完了条件**：照合待ち → 対応表の登録 → 受注確定 → 発注が「受注済」、の通しのテスト。発注側から対応表が見えないことを行列テストで確かめる。

**実装する文書の節**：`context-map.md`「発注の連結と品番の照合」5

## M12 在庫と引当

**目的**：有効在庫は負にならない。在庫の変更は必ず 1 つの内部メソッドを通り、移動履歴を残す。全量を引き当てた受注だけが出荷可能になる。

**作るもの**

- `stocks`・`allocations`・`stock_movements`、在庫の内部メソッド
- `Inventory::Allocation`（引当・解除・消費・受注明細 ID ごとの量）・`Inventory::Stocks`・`Inventory::Adjustment`
- `Sales::OrderAllocation.allocate`、受注の状況の「引当済」「一部引当」
- 出荷可能のイベント（受け手は M13）
- `supplier.stocks`・`supplier.stockMovements`・`Item.stock`・`SalesOrderLine.allocatedQuantity`、`adjustStock`・`allocateSalesOrder`

**完了条件**：有効在庫を超える引当が DB の CHECK 制約で拒否されるテスト。引当と調整のたびに移動履歴が 1 行増えるテスト。ロックの順（受注 → 受注明細 → 在庫 → 引当）をテストの中で確かめる。

**実装する文書の節**：`data-model.md`「在庫（`inventory`）」「取消と出荷の競合を止める場所」のロックの順、`context-map.md`「コンテキスト間の関係」の受注 → 在庫

## M13 出荷指示と出荷実績の計上

**目的**：出荷は `active` の引当だけを消費する。有効な出荷指示は出荷依頼ごとに 1 件である。

**作るもの**：`shipment_requests`・`shipment_request_lines`・`shipping_instructions`・`shipments`・`shipment_lines`、出荷可能の受け手、`Fulfillment::Instructions`・`Fulfillment::Shipping.post`・`Fulfillment::ShipmentRequests`、`supplier.shipmentRequests`・`SalesOrder.shipmentRequest`、`createShippingInstruction`・`cancelShippingInstruction`・`postShipment`、出荷計上のイベント

**完了条件**：計上で引当が `consumed` になり、在庫が減るテスト。`active` でない引当での計上が中止されるテスト。出荷依頼の状況の導出表の各行のテスト（「出荷停止中」は M15 で足す）。

**実装する文書の節**：`data-model.md`「出荷（`fulfillment`）」、`context-map.md`「コンテキスト間の関係」の受注 → 出荷・出荷 → 在庫

## M14 出荷計上の還流と経路 3

**目的**：「出荷計上」が受注と購買の両方に届き、それぞれのテナントの名義で書かれる。読む経路 3 は、`view_shipments` の付与があり、自社の発注に連結した出荷だけを見せる。

**作るもの**：受注の受け手（`shipped_at`）、購買の受け手（`inbound_shipments`・明細）、経路 3 の `partner_read` ポリシー、`Fulfillment::PartnerShipments.for_purchase_orders`、`PurchaseOrder.inboundShipments`・`PurchaseOrder.supplierShipments`

**完了条件**：1 つの出荷計上が 2 つの宛先テナントでそれぞれ 1 回だけ処理されるテスト。行列テストで、経路 3 が `granted_buyer` の自社の発注にだけ開く。`SupplierShipment` が出荷実績 ID を返さず、到達可能性のテストの 3 つ目（相手側の型が 3 つちょうど）がここで満たされる。

**実装する文書の節**：`graphql-schema.md`「発注側の視点」の経路 3、`data-model.md`「RLS」の経路 3

## M15 取消依頼と審査

**目的**：発注側の取消は、受注側の承認でだけ成立する。審査中は出荷の指示と計上が止まる。

**作るもの**：`cancellation_requests`・`cancellation_reviews`・`shipping_holds`、取消依頼・出荷停止・出荷停止解除・取消承認・取消却下・出荷取消のイベント、出荷済みの受注への取消依頼の自動却下、`requestPurchaseOrderCancellation`・`approveCancellationReview`・`rejectCancellationReview`、受注と発注の状況の「取消審査中」「取消依頼中」

**完了条件**：依頼 → 停止 → 承認 → 発注が「取消済み」・出荷依頼が「取消済」の通しのテスト。依頼 → 却下 → 発注が元の状況に戻る通しのテスト。審査中の出荷の計上が拒否されるテスト。

**実装する文書の節**：`context-map.md`「取消の流れ」1〜4、`data-model.md`「出荷（`fulfillment`）」の出荷停止

## M16 受注側の取消と、取消と出荷の競合

**目的**：受注側は審査なしで取り消せる。同時に進んだ取消と出荷計上は、引当の行ロックでどちらか一方だけが成立する。

**作るもの**：`Sales::OrderCancellation.cancel`、受注取消のイベントと購買の受け手（`supplier_cancelled_at`）、`cancelSalesOrder`

**完了条件**：`spec/concurrency/cancel_vs_ship_spec.rb`：2 つの接続で取消と計上を同時に走らせ、どちらか一方だけが成立することを繰り返して確かめる。このテストはトランザクションで包まない設定で動かし、作った行を後で消す。

**実装する文書の節**：`context-map.md`「取消の流れ」の受注側の取消、`data-model.md`「取消と出荷の競合を止める場所」

## M17 検収

**目的**：検収数量は出荷数量を超えない。検収は入荷 1 件に 1 回で、受注側へ 1 回だけ届く。

**作るもの**：`receipt_inspections`・明細、`inspection_records`、`Purchasing::ReceiptInspection.record`、検収完了と請求対象確定のイベント（請求対象確定の受け手は M18）、受注の「検収済」、`inspectInboundShipment`、`InboundShipment.inspection`・`InboundShipmentLine.acceptedQuantity`

**完了条件**：出荷数量を超える検収が `INVALID_INPUT` になるテスト。すべての出荷実績が検収されたときだけ受注が「検収済」になるテスト。

**実装する文書の節**：`context-map.md`「検収と請求の流れ」1〜3、`data-model.md`「購買」「受注」の検収の表

## M18 請求の締め

**目的**：締めは取引先ごとに直列になる。消費税は請求書・税率ごとに 1 回だけ切り捨てる。前の期間の遅れた検収も次の締めで拾う。

**作るもの**：`billing_terms`・`billable_items`・`invoices`・`invoice_tax_summaries`、請求対象確定の受け手、`Billing::Terms`・`Billing::BillableItems`・`Billing::Closing.close`・`discard`、`supplier.billingTerms`・`supplier.billableItems`・`supplier.invoices`・`supplier.invoice`、`setBillingTerm`・`closeBillingPeriod`・`discardDraftInvoice`

**完了条件**：税率 8% と 10% が混ざる明細で、税額が明細ごとの丸めの合計と異なる例を含むテスト。末日締め（31）のテスト。下書きの破棄で明細が未請求に戻るテスト。

**実装する文書の節**：`data-model.md`「請求（`billing`）」、`context-map.md`「検収と請求の流れ」4・5 と請求書の組み立ての規則

## M19 請求書の発行と受領請求書

**目的**：確定した請求書と明細は変わらない。写しは発注側の名義で 1 回だけ作られる。

**作るもの**：`Billing::Closing.issue`、請求書発行のイベント、購買の受け手（`received_invoices`・明細）、`Purchasing::ReceivedInvoices`、`issueInvoice`、`buyer.receivedInvoices`・`buyer.receivedInvoice`

**完了条件**：確定後の変更が拒否されるテスト。同じ請求書発行を 2 回流しても写しが 1 件のテスト。`total = subtotal + tax_total` の CHECK 制約のテスト。

**実装する文書の節**：`context-map.md`「検収と請求の流れ」5・6、`data-model.md`「購買」の受領請求書

## M20 ダッシュボードと失効の通し試験

**目的**：取引関係を失効させると 3 つの読む経路と新しい発注が閉じ、連結済みの取引はイベントで請求まで進む。この見せどころを 1 本のテストで示す。

**作るもの**

- `supplier.dashboard`（`graphql-schema.md`「読み取りの一覧」の 4 つの公開 API）
- `spec/scenarios/revocation_spec.rb`：発注 → 受注確定 → 失効 → 経路 1〜3 が空・新しい発注が `NOT_PERMITTED` → 引当・出荷・検収・締め・発行がそのまま進み、発注側に受領請求書が届く
- 画面の問い合わせごとの複雑度のテスト（`graphql-schema.md`「ページングと N+1」）

**完了条件**：上の 2 つのテストが通る。全マイルストーンの共通の完了条件が通る。

**実装する文書の節**：`context-map.md`「取引関係の失効」「テナントと所有」のデモの見せどころ

## M21 シードデータ

**目的**：デモを開いた人が、両方の視点と 3 つの読む経路をすぐ見られる。

**作るもの**：`db/seeds.rb`。受注側に青嵐精機工業、発注側に架空の組立メーカー 2 社（全権限の付与あり・失効済み）を作る。factory-ops-demo の品目と得意先を写し、受注・出荷・検収・請求書まで進んだ取引と途中の取引を混ぜる。シードは公開 API とイベントを通して作り、表へ直接書かない。

**完了条件**：`bin/rails db:reset` が通り、両社のユーザーでログインして `buyer`・`supplier` の主な問い合わせが値を返す。

## M22 フロントエンド

当面は範囲外とする。M21 までが終わってから計画を立てる。方針は、factory-ops-demo の Next.js を流用し、データ取得層を REST から GraphQL へ書き換え、発注側の画面を足すことである（`handoff.md`「目的」）。
