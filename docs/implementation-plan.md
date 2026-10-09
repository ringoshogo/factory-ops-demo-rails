# 実装計画

設計文書（`architecture/`・`adr/`）を、動くアプリに落とす順番を定める。実装を担当するエージェントは、マイルストーンを M1 から番号の順に 1 つずつ実装する。1 つのマイルストーンは 1 回の作業で終わる大きさ（数百行）にしてある。

## 1 つのマイルストーンの進め方

担当者は、マイルストーンに着手するたびに次の順で進める。

1. 本書の該当節を読み、「実装する文書の節」に挙げた設計文書の節を読む。
2. 「作るもの」を実装する。設計文書に書いていないことを決めたら、「文書に残すこと」に挙げた文書へ、同じ作業の中で書き足す。設計文書と食い違う実装にしたときも、先に文書を直す。
3. 「完了条件」と「共通の完了条件」をすべて通す。1 つでも落ちていれば、次のマイルストーンへ進まない。
4. `handoff.md` の「リポジトリの状態」に、終えたマイルストーンを書く。

設計文書の規則を守る仕組みは、テスト・packwerk・基底クラス・DB の制約のどれかで作る。規則をコメントや README にだけ書いて終えない。

マイルストーンの節に「判断」がある場合は、そこに既定の推奨・裏返る条件・撤退コストを書いてある（`architecture/decisions.md` と同じ形）。担当者は、着手の時点で裏返る条件に当たっていないかを確かめてから実装する。当たっていれば、作者に確かめる。

### 共通の完了条件

M2 以降のすべてのマイルストーンで、次のコマンドが成功する。CI（M1 で作る）も同じものを実行する。検査を足したマイルストーンより後では、その検査も共通の完了条件に加わる。

```sh
bin/rubocop                                   # M15 からコメントの規約の Cop を含む
bin/packwerk validate && bin/packwerk check   # M2 から
bundle exec rspec --format progress --format json --out tmp/rspec.json
bin/test-layers tmp/rspec.json                # M16 から。テストの層ごとの件数の報告
bin/check-structure                           # structure.sql の往復の検査
bin/check-schema-compat                       # M20 から。GraphQL のスキーマの破壊的変更の検査
```

`bin/check-structure` は、開発の DB にマイグレーションを流した結果と、`structure.sql` を読み込み直して書き出した結果が、どちらも `structure.sql` と一致することを確かめる。空の DB への `db:migrate` は `structure.sql` を読み込むだけでマイグレーションを流さないので、`structure.sql` を退避してから流す。文字列の列の CHECK 制約は `status::text IN (...)` と書く。`status IN (...)` と書くと、マイグレーションの結果と読み込み直した結果で式の表記が変わり、この検査が落ちる。

packwerk の違反は `package_todo.yml` に逃がさず、その場で直す（`adr/002`）。

## 環境

次の値は決まっている。担当者は変えない。

| 項目 | 値 |
|---|---|
| Ruby | 3.3.3（rbenv）。3.3.0 は構文解析の不具合（Ruby bug #20090）で Rails 8.1 の Action View を読み込めない |
| Rails | 8.1 系、API モード |
| DB | PostgreSQL 18（`docker compose` の `postgres:18`）。開発とテストの両方で使う。拡張は `btree_gist`（M27、`adr/006`）だけを入れる |
| pg_dump | 18 系。手元は Homebrew の `libpq`（keg-only）を PATH の先頭に足して使い、CI は PGDG の `postgresql-client-18` を入れる |
| GraphQL | graphql-ruby、Action Policy（`action_policy-graphql`）。スキーマの比較は graphql-schema_comparator（M20） |
| ジョブ | Solid Queue を業務 DB と同じ DB・同じ接続に置く（`adr/005`）。キューとワーカーの分け方は `adr/007` |
| パッケージ | packs-rails、packwerk、packwerk-extensions（`adr/002`） |
| スキーマ | Rails マイグレーション＋`db/structure.sql`、strong_migrations（`adr/001`） |
| テスト | RSpec（rspec-rails）＋FactoryBot。N+1 の検出は Bullet（M17）、外部への HTTP の遮断は WebMock（M28） |
| 静的解析 | rubocop-rails-omakase を起点にする（`decisions.md` 7 章） |
| ログ | Rails 8.1 の `Rails.event` を出口にした 1 行 1 件の JSON（M18） |
| メトリクス | Yabeda＋yabeda-prometheus（M30） |

手元には PostgreSQL 16 が入っている。`uuidv7()` は 18 にしか無いので、DB は必ずコンテナの 18 を使う。

## マイルストーンの一覧

骨組み（M1〜M7）を先に作り、業務機能（M8〜M14）を業務の流れの順に、薄い縦切りで足した。業務機能の各マイルストーンは、テーブル・公開 API・policy・イベント・GraphQL のフィールド・行列テストの行を 1 つの単位で作る。

残りの業務機能（M21〜M26）の前に、横断の仕組み（M15〜M20）を入れる。横断の仕組みは、mutation の宣言・イベントの引数・テストの置き場・CI の検査を変える。業務機能の後に入れると、M21〜M26 で書いた mutation・イベント・テストを書き直すことになる。業務機能を終えた後に、見せどころ（M27〜M31）を足す。最後に、シード（M32）と、それを使って E2E を流すフロントエンド（M33）を作る。

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
| M15 | コメントの規約と掃除 | コメントに開発の経緯・マイルストーンの番号・予定を書けない |
| M16 | テストの層と重要シナリオ | どのテストも層に分類され、層ごとの件数が CI で毎回報告される |
| M17 | N+1 の検出 | 関連を 1 件ずつ読む N+1 と、親の数でクエリが増える問い合わせがテストで落ちる |
| M18 | 構造化ログと相関 ID | ログが 1 行 1 件の JSON で文脈を持ち、テナントをまたぐ一連の処理が 1 つの相関 ID で引ける |
| M19 | 監査ログ | 相手テナントに効果が及ぶ書き込みが必ず記録され、記録は書き換えも削除もできない |
| M20 | GraphQL スキーマの破壊的変更の検出 | 非推奨を経ない破壊的変更が CI を通らない |
| M21 | 取消依頼と審査 | 審査中は出荷が止まり、取消は受注側の承認でだけ成立する |
| M22 | 受注側の取消と、取消と出荷の競合 | 同時に進んだ取消と出荷のどちらか一方だけが成立する |
| M23 | 検収 | 検収数量が出荷数量を超えず、検収が受注側へ 1 回だけ届く |
| M24 | 請求の締め | 締めが取引先ごとに直列になり、税が請求書・税率ごとに 1 回だけ丸められる |
| M25 | 請求書の発行と受領請求書 | 確定した請求書が変わらず、写しが発注側に 1 回だけ届く |
| M26 | ダッシュボードと失効の通し試験 | 失効の後も連結済みの取引が請求まで進む |
| M27 | 販売単価のバイテンポラル履歴 | 現在の単価の有効期間が重ならず、単価の行が書き換わらない |
| M28 | 外部サービスの呼び出しと非同期の型 | 外部への作用が 1 つの登録口からだけ登録され、テストと開発で本物の SendGrid を呼べない |
| M29 | 大量データの取り込み | 取り込みが他のキューを待たせず、中断しても続きから再開し、他社の名義で書けない |
| M30 | メトリクス | メトリクスのラベルにテナントとユーザーが入らない |
| M31 | SLO と障害対応の手順書 | どの警報も手順書を持ち、警報の規則が CI で検査される |
| M32 | シードデータ | — |
| M33 | フロントエンド | 画面の問い合わせが `schema.graphql` で型検査され、同じ種類の要素の寸法とそろえが全画面で測られる（計画済み。実装は M32 の後） |

`handoff.md` は骨組みを「パッケージ構成 → テナントの強制 → 行列テスト → イベント」の 4 つにしていた。本書はこれに 2 つ足した。1 つは M1（`rails new`・DB・CI）で、他のすべての前提になる。もう 1 つは M5（GraphQL の基盤）で、行列テストの「入口」の軸が GraphQL のフィールドなので、行列テストの枠より先に要る。テナントの強制は、DB の仕組み（M3）とリクエストの入口（M4）に分けた。1 回の作業に収めるためである。

M15 以降は、番号の順のほかに、次の前提を持つ。前提のマイルストーンを終えるまで着手しない。

| マイルストーン | 前提 | 前提が要る理由 |
|---|---|---|
| M16 | M14 | シナリオ S1・S3 が、M14 までの発注・連結・出荷の流れを使う |
| M17 | M5 | Dataloader のソースと、画面の問い合わせの一覧を使う |
| M18 | M4・M7 | 文脈を `GraphqlController` と `ApplicationJob`・`Contracts::EventJob` で設定する |
| M19 | M18 | 監査ログの相関 ID を、M18 の文脈から取る |
| M20 | M5 | スキーマを書き出す |
| M21〜M26 | M15〜M20 | 新しい mutation に監査の宣言を、イベントに付帯情報を、テストに層を、型の変更に `schema.graphql` の書き直しを伴わせる |
| M27 | M19・M20・M25 | 単価の変更を監査する。請求書の説明が発行済みの請求書を使う |
| M28 | M18・M25 | 送信の失敗をログに出す。確実な通知の呼び出し元が「請求書発行」の受け手である |
| M29 | M27・M18 | 単価の列を `Sales::ItemPrices` で反映する。進み具合をログに出す |
| M30 | M18・M28・M29 | 値の出どころが M18 の構造化イベントで、外部の呼び出しと取り込みの値も測る |
| M31 | M30 | SLO と警報を M30 のメトリクスで書く |
| M32 | M31 まで | シードが単価の履歴と取り込みも含む |
| M33 | M32 | 画面が呼ぶ入口が M29 までにそろい、E2E の世界を M32 のシードと同じ形で作る |

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
- API モードに Cookie とセッションのミドルウェアを足し、Cookie を `SameSite=Lax` にし、期限を最後のリクエストから 12 時間にする。ログアウトとパスワードの変更でセッションの世代を進め、前の Cookie を使えなくする。
- graphql-ruby を入れ、`viewer` だけを持つスキーマを置く。
- `GraphqlController`：POST の `application/json` だけを受け付ける。`Tenancy.with_tenant` でスキーマの実行全体を包み、RLS の下でユーザーを引いて `Current.actor` に設定する。引けないか、セッションの世代（`users.session_version`）が違えば実行せずに 401 を返す。例外かトップレベルのエラーならロールバックし、それ以外はユーザーエラーを返した場合も含めてコミットする。
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

  M8 で取引関係の表ができるまでは、`supplier` と `stranger` の 2 つで始め、M8 で残りを足す。`revoked_buyer` の取引関係は全権限の付与を持ったまま失効させ、付与が残っていても失効で閉じることを確かめる。
- **表の行列**（`spec/matrix/table_matrix_spec.rb`）：`owner_tenant_id` を持つ全表を DB から列挙し、ペルソナごとに、生 SQL で読める行の件数を所有者ごとに数え、相手名義の INSERT・相手の行への UPDATE と DELETE・自社の行を相手名義へ書き換える UPDATE を確かめる。期待値は `spec/matrix/table_expectations.rb` に全表の行を書く。既定は `OWNER_ONLY`（所有者だけが読める）で、読む経路の表（`items`・`partnerships`・`partnership_grants`・`shipments`・`shipment_lines`）だけに、読むペルソナと、見える相手の行の件数を書く。行の無い表があれば落ちる。世界の行は FactoryBot で作り、テナントの表ごとに、表の単数形の名前の factory があることも確かめる。factory は表を持つパッケージの `spec/factories` に置く（packs-rails が読み込む）。
- **入口の行列**（`spec/matrix/graphql_matrix_spec.rb`）：スキーマから `BuyerView`・`SupplierView`・`Query`（視点の入口を除く）の全フィールドと全 mutation、それに入口より下で相手側の型（`cross_tenant_read` を宣言した型）を返すフィールド（`SupplierPartnership.catalog` など）を列挙し、ペルソナとしてログインして実行し、結果の種類（値が返る・空・`null`・`NOT_FOUND`・`NOT_PERMITTED`・`FORBIDDEN`）が `spec/matrix/graphql_expectations.rb` の期待と一致することを確かめる。期待値の無いフィールドや mutation、全ペルソナの期待が揃っていない行があれば落とす。入口より下のフィールドは、親の一覧（経路 2 の `buyer.suppliers`）の要素ごとにたどって値を集め、どの要素でも空なら「空」とする。読む経路は入れ子のフィールドとして現れるので、入口だけを列挙すると経路 1・3 が行列から漏れるからである。
- 業務機能のマイルストーンは、この 2 つの期待値のファイルに行を足すだけで行列テストを増やせる。入口より下に読む経路を足すとき（M14 の `PurchaseOrder.supplierShipments`）は、`graphql_matrix_spec.rb` の `parent_paths` に、親の型までの道も足す。

**完了条件**

```sh
bundle exec rspec spec/matrix
```

期待値のファイルから `users` の行を消すと、表の行列が落ちることを手で確かめる。

**実装する文書の節**：`context-map.md`「テナントと所有」、`showcase.md`「1. テナントの境界：読む 3 経路、書けないこと、失効」、`decisions.md` 7 章（実行時のゲートと列挙テスト）

## M7 イベントの登録と受信

**目的**：イベントのジョブは業務データと同じトランザクションで登録され、ロールバックすれば消える。受け手は宛先テナントの名義で、冪等に処理する。発行元は受け手を知らない。

**作るもの**

- Solid Queue を入れ、`db/queue_schema.rb` の内容を通常のマイグレーションに写す。`queue` の DB と `connects_to` は作らない。`config.active_job.queue_adapter = :solid_queue` を `config/application.rb` に書く。`solid_queue_*` を M3 の列挙テストの除外宣言に足す。
- `ApplicationJob`（`packs/platform`）：`self.enqueue_after_transaction_commit = true`。投入時の `Current.tenant_id` を引数に載せ、実行時に `Tenancy.with_tenant` で復元する（`decisions.md` 2 章）。
- `packs/contracts`：
  - イベントの型（`Contracts::Event.define`）。ID と、受け手が要る値の写しだけを持つ。ジョブの引数には、イベントの名前・プリミティブだけのハッシュ・受け手のクラス名・宛先テナント ID を渡す。
  - 配送表 `Contracts::Subscriptions`：イベントごとに、受け手のクラス名（文字列）と、宛先テナントを示すペイロードの項目を並べる。1 つのイベントが別のテナントの 2 つの受け手へ届く（「出荷計上」）ので、宛先は受け手ごとに書く。受け手を文字列で書くので、`contracts` は受け手のパッケージに依存しない。
  - `Contracts.publish(event)`：配送表の受け手ごとに `Contracts::EventJob` を 1 件ずつ登録する。トランザクションの外で呼ばれたら例外にする。
  - `Contracts::EventJob`（`ApplicationJob` を継承）：`self.enqueue_after_transaction_commit = false`。実行時に、宛先テナントで `Tenancy.with_tenant` を開き、受け手の `handle(event)` を呼ぶ。宛先テナントは配送表の項目が指すペイロードの値から決める。`Contracts.publish` の外での登録と継承を、実行時にも拒む。`limits_concurrency` を付けない。
- `spec/jobs/event_job_atomicity_spec.rb`（`adr/005` 決定 4 の 3 つ）。
- `spec/contracts/subscriptions_spec.rb`：配送表のクラス名がすべて定数として存在し、`handle` を持つこと。
- テストでのジョブの扱い：テストでも Active Job の `:test` アダプタに差し替えず、`:solid_queue` のまま `solid_queue_jobs` の行を読む。登録したイベントを受け手まで流す補助（`spec/support/events.rb` の `deliver_enqueued_events`）を作り、業務機能のテストはこれで流す。`event_job_atomicity_spec` の中で、`Contracts::EventJob.queue_adapter` が Solid Queue のアダプタであることも確かめる。
- 受け手の雛形と冪等の確かめ方：同じイベントを 2 回流しても書いた行が 1 件であることを、受け手ごとのテストに書く（`spec/support/shared_examples/idempotent_receiver.rb`）。
- カスタム Cop（`lib/rubocop/cop/factory_ops/`）：`Contracts::EventJob.perform_later` と `SolidQueue::Job` への書き込み（`enqueue`・`create` など）を、`Contracts.publish` の外で禁止する（`decisions.md` 5 章「投入経路を Active Job 経由に限る」）。テストの補助が `solid_queue_jobs` の行を読むのは禁止しない。

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

M8〜M14 と M21〜M26 の担当者は、各マイルストーンで次を作る。マイルストーンの節には、それぞれに固有のものだけを書く。

- 表は `create_tenant_table` で作り、親子は `add_tenant_reference` でつなぐ。他コンテキストへの参照は ID 列だけにする。
- 状況の導出は、`data-model.md`「状態は保存せず、時刻列から導出する」の表のとおりに公開 API で行い、表の各行に 1 つずつテストを書く。
- 公開 API は操作者を必須の引数にし、policy の `relation_scope` を掛けてから値を返す。失敗を返す操作は `transaction(requires_new: true)` の中で書き、失敗を返す前にセーブポイントまで戻す。
- イベントの受け手には、冪等の共有テスト（M7）を適用する。
- GraphQL の型・リゾルバ・mutation は M5 の基底クラスから作り、行列テストの期待値（M6）に行を足す。

M21 以降は、横断の仕組み（M15〜M20）に合わせて、次も作る。

- mutation には、監査の宣言（`audit` か `audit_exempt reason:`）を書く。相手テナントへイベントを出す mutation は `audit` にする（`architecture/graphql-schema.md`「監査ログ」）。
- 業務規則の分岐は公開 API の単体テスト（`packs/*/spec`）で網羅し、request spec は入口ごとに成功と失敗の写し方を 1 本ずつにする。重要シナリオの表（M16）に載ったものは、`spec/scenarios` か `spec/concurrency` に書く。
- GraphQL の型を変えたら、`bin/rails graphql:schema:idl` で `schema.graphql` を書き直し、同じ commit に入れる。
- 公開 API の中で、値の組み立てに要る関連を先読みする（M17）。ログのペイロードには ID・コード・件数だけを入れる（M18）。

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

**完了条件**：計上で引当が `consumed` になり、在庫が減るテスト。`active` でない引当での計上が中止されるテスト。出荷依頼の状況の導出表の各行のテスト（「出荷停止中」は M21 で足す）。

**実装する文書の節**：`data-model.md`「出荷（`fulfillment`）」、`context-map.md`「コンテキスト間の関係」の受注 → 出荷・出荷 → 在庫

## M14 出荷計上の還流と経路 3

**目的**：「出荷計上」が受注と購買の両方に届き、それぞれのテナントの名義で書かれる。読む経路 3 は、`view_shipments` の付与があり、自社の発注に連結した出荷だけを見せる。

**作るもの**：受注の受け手（`shipped_at`）、購買の受け手（`inbound_shipments`・明細）、経路 3 の `partner_read` ポリシー、`Fulfillment::PartnerShipments.for_purchase_orders`、`PurchaseOrder.inboundShipments`・`PurchaseOrder.supplierShipments`

**完了条件**：1 つの出荷計上が 2 つの宛先テナントでそれぞれ 1 回だけ処理されるテスト。行列テストで、経路 3 が `granted_buyer` の自社の発注にだけ開く。`SupplierShipment` が出荷実績 ID を返さず、到達可能性のテストの 4 つ目（相手側の型が 3 つちょうど）がここで満たされる。

**実装する文書の節**：`graphql-schema.md`「発注側の視点」の経路 3、`data-model.md`「RLS」の経路 3

---

## 横断の仕組みのマイルストーンに共通すること

M15〜M20 は、業務の表を足さず、すでにある mutation・イベント・テスト・CI に仕組みを足す。担当者は、仕組みを入れるときに、M8〜M14 で作った既存のコードもすべて新しい規則に合わせる。新しい規則に合わない既存のコードを、例外の一覧に入れて残さない。

## M15 コメントの規約と掃除

**目的**：コードのコメントが、いまの振る舞いと理由だけを書き、開発の経緯・マイルストーンの番号・予定を書かない（`guides/comments.md`）。チームの人が入れ替わっても、コメントが古い経緯で読む人を誤らせない。

**作るもの**

- カスタム Cop `FactoryOps/NoHistoryComment`（`lib/rubocop/cop/factory_ops/no_history_comment.rb`）：`processed_source.comments` を走査し、`guides/comments.md`「機械で止めるもの」の語を含むコメントを落とす。マイルストーンの番号は `(?<![A-Za-z0-9_])M\d+(?![A-Za-z0-9_])` で判定する。`\b` は和文の文字を語の一部とみなすので、「停止中はM15で足す」のように和文に挟まった番号を見逃す。`.rubocop.yml` で全 Ruby ファイルに有効にする。
- `spec/rubocop/cop/factory_ops/no_history_comment_spec.rb`：`guides/comments.md` の良い例が通り、悪い例が落ちることを確かめる。
- 既存のコメントの掃除：Cop が落とす箇所をすべて書き直す。spec の冒頭のコメントは、`implementation-plan.md` のマイルストーンではなく、その spec が守る規則と設計文書の節を指す形にする。コードに残っている `M15`・`M17` などの番号は、本書の番号を付け直す前のもので、いまの M15・M17 とは別物である。番号で指していた先は、設計文書の節に置き換える。

**判断**：コメントの規約を Cop で止めるか、レビューに任せるか

- **既定の推奨**：語の一覧で止める Cop を置く。規約を文書にだけ書くと、人が入れ替わるたびに消える（`decisions.md` 7 章）。語で判定できない規則（コードの言い直しをしない、など）はレビューに残す。
- **裏返る条件**：誤検知で言い換えが日常になり、Cop を無効にするコメントが増える → 語の一覧を絞り、外した語をレビューの観点に移す。
- **撤退コスト**：小さい。Cop を外すだけで済む。

**完了条件**

```sh
bin/rubocop
bundle exec rspec spec/rubocop
git grep -nP "#.*(?<![A-Za-z0-9_])M\d+(?![A-Za-z0-9_])" -- '*.rb' '*.rake' | wc -l   # 0
```

番号の検索は `-P` で流し、番号の前後は ASCII の英数字で区切る。macOS の git は `-E` の `\b` を解さないことがあり、番号が残っていても 0 を返す。`\b` は和文の文字も語の一部とみなすので、和文に挟まった番号を見逃す。

**実装する文書の節**：`guides/comments.md`、`decisions.md` 7 章

**文書に残すこと**：Cop の語の一覧を変えたら、`guides/comments.md`「機械で止めるもの」を同じ変更で直す。

## M16 テストの層と重要シナリオ

**目的**：テストの大半を、速く、落ちた場所から原因が分かる単体テスト（公開 API・モデル・policy）に置く。壊れると事故になる業務の流れだけを、専用のシナリオテストで端から端まで確かめる。CI は、層ごとの件数・割合・時間を毎回報告する。

**作るもの**

- テストの層の定義（`config/test_layers.yml`）。担当者は、テストのファイルを足すとき、どの層の置き場に置くかを次の表で決める。

  | 層 | 置き場 | 確かめること | 件数の目安 |
  |---|---|---|---|
  | 単体 | `packs/*/spec` | 1 つのパッケージの公開 API・モデル・policy・状況の導出。DB は使うが、GraphQL とイベントの配送は通さない | 60% 以上 |
  | 結合 | `spec/requests`・`spec/contracts` | GraphQL の入口から公開 API までの配線、イベントの配送表と受け手のつながり | 30% 以下 |
  | シナリオ | `spec/scenarios`・`spec/concurrency` | 下の重要シナリオ | 10% 以下 |
  | ガード | `spec/matrix`・`spec/graphql`・`spec/db`・`spec/packwerk`・`spec/jobs`・`spec/platform`・`spec/rubocop` | 構造の規則（列挙テスト・行列テスト・到達可能性・テナントの強制） | 数えない |

  割合は、単体・結合・シナリオの 3 つの層の example の数で数える。ガードは、表・型・入口の数に比例して増えるので、割合に数えない。

- 層への配分の規則：業務規則の分岐（数量の上限、状況ごとの拒否、導出表の各行）は、単体で網羅する。結合の request spec は、入口ごとに、成功 1 本と、公開 API の失敗が `UserError` に写ること 1 本に絞る。既存の request spec のうち、公開 API の spec と同じ分岐を確かめているものは、単体へ移す。
- `bin/test-layers`：rspec の JSON の出力を読み、層ごとの件数・割合・時間を表にして、標準出力と `$GITHUB_STEP_SUMMARY` に書く。どの層の置き場にも当たらないファイルがあれば失敗する。割合が目安を外れたら、GitHub の警告の注釈（`::warning::`）を出す。
- CI の rspec のステップを、共通の完了条件のとおり JSON も書く形にし、続けて `bin/test-layers` を流す。
- 重要シナリオ。シナリオは 2 社のユーザーとして GraphQL を通して操作し、`:solid_queue` のまま `deliver_enqueued_events` でイベントを流す。`spec/concurrency` は、トランザクションで包まない設定で 2 つの接続から同時に操作し、作った行を後で消す。どれも `:scenario` のタグを付け、`bundle exec rspec --tag scenario` で単独で流せるようにする。

  | | シナリオ | 確かめること | 置き場 | 作るマイルストーン |
  |---|---|---|---|---|
  | S1 | テナントの境界 | 発注側が、イベントで受け取った相手の ID（出荷実績 ID）と、受注側の伝票の ID を、すべての ID の入口と mutation に持ち込んでも、相手のデータに届かない（`null` か `NOT_FOUND`） | `spec/scenarios/tenant_boundary_spec.rb` | M16 |
  | S2 | 取引関係の失効 | 失効で 3 経路と新しい発注が閉じ、連結済みの取引は請求まで進む | `spec/scenarios/revocation_spec.rb` | M26 |
  | S3 | 発注と受注の連結 | 照合待ち → 対応表の登録 → 受注確定。同じイベントを 2 回流しても、イベントの届く順を入れ替えても、受注は 1 件で、発注の状況は同じになる | `spec/scenarios/order_linking_spec.rb` | M16 |
  | S4 | 引当・出荷・取消の競合 | 同じ出荷依頼の同時の計上は 1 件だけ成立する。同時の引当と出庫で有効在庫が負にならない。同時の取消と計上はどちらか一方だけが成立する | `spec/concurrency/` | M16（計上・引当）、M22（取消） |
  | S5 | 請求の金額と税の丸め | 発注 → 受注 → 出荷 → 検収 → 締め → 発行 → 受領請求書で、単価・数量・税額・合計が 2 社で一致し、税が請求書・税率ごとに 1 回だけ切り捨てられる | `spec/scenarios/billing_amounts_spec.rb` | M25 |

- 行列テストとの分担：行列テスト（M6）は、全表・全入口を 5 つのペルソナで 1 段ずつ確かめる。シナリオは、段をつないだ道（イベントで知った ID を別の入口に持ち込む、など）を確かめる。行列テストに行を足して済むものは、シナリオにしない。

**判断**：層の割合を CI の失敗にするか

- **既定の推奨**：報告と警告にとどめ、未分類のファイルだけを失敗にする。割合は機能の種類で揺れる（GraphQL の入口だけを足すマイルストーンでは結合が増える）。未分類を止めれば、数え方は崩れない。
- **裏返る条件**：3 マイルストーン続けて目安を外れる → 単体の割合の下限を失敗の条件に変える。
- **撤退コスト**：小さい。`bin/test-layers` の終了コードを変えるだけで済む。

> 手で書いた example の数（行列テストのように生成する分を除く）は、M14 の時点で、単体（`packs/*/spec`）が約 90、結合（`spec/requests`・`spec/contracts`）が約 90 だった。

**完了条件**

```sh
bundle exec rspec --format json --out tmp/rspec.json
bin/test-layers tmp/rspec.json   # 層ごとの表が出て、未分類のファイルが無い
bundle exec rspec --tag scenario
```

`spec/scenarios/tenant_boundary_spec.rb` の期待を 1 つ外すと落ちることを、手で確かめる。

**実装する文書の節**：`decisions.md` 7 章、`adr/005` 決定 6（テストでのジョブの扱い）

**文書に残すこと**：層の定義と重要シナリオの表を `guides/testing.md` に移し、本節からはそこを参照する。

## M17 N+1 の検出

**目的**：公開 API の中で関連を 1 件ずつ読む N+1 を、Bullet でテストの失敗にする。GraphQL のフィールドが親ごとに公開 API を呼ぶ N+1 は Bullet に見えないので、問い合わせごとのクエリ数の予算で落とす。

**作るもの**

- Bullet を test と development のグループに入れる。`config/environments/test.rb` は `Bullet.enable`・`Bullet.raise`・`Bullet.n_plus_one_query_enable` を真に、`Bullet.unused_eager_loading_enable`・`Bullet.counter_cache_enable` を偽にする。development は `Bullet.bullet_logger` で記録だけにする。
  - 使わない先読みの検出を外す理由：`Bullet.raise` は検出の種類を問わず例外にする。公開 API は、値の組み立てに要る関連を GraphQL の選択によらずまとめて先読みするので、使わない先読みの報告は直す対象にならない。
  - カウンタキャッシュの検出を外す理由：状況と件数は時刻列と公開 API で導出し（`data-model.md`「状態は保存せず、時刻列から導出する」）、カウンタキャッシュの列を持たない。
- `spec/support/bullet.rb`：各 example を `Bullet.start_request` と `Bullet.end_request` で包む。`spec/concurrency` は別のスレッドで操作するので、対象から外す。
- 許可リスト：`spec/support/bullet_safelist.rb` に `{ type:, class_name:, association:, reason: }` の配列で書き、`Bullet.add_safelist` に渡す。`reason` の無い行は、読み込みの時点で例外にする。許可してよいのは、件数が 1 に決まっている誤検知（1 件のレコードを引いてから関連をたどる、など）だけである。本当の N+1 を許可リストで黙らせない。
- 画面の問い合わせの一覧（`spec/fixtures/graphql/screens/*.graphql`）：画面が送る問い合わせを、操作名を付けて 1 ファイル 1 つで置く。M14 までの画面の問い合わせで作り、後のマイルストーンは画面の問い合わせを足すたびにここへ足す。M26 の複雑度のテストと M30 の操作名の登録も、この一覧を使う。
- `spec/graphql/query_budget_spec.rb`：画面の問い合わせの一覧の問い合わせごとに、一覧の親が 1 件のときと 20 件のときの SQL の件数を比べ、同じであることを確かめる。件数は `sql.active_record` を購読して数え、`SCHEMA`・`TRANSACTION` の名前のものと `SET LOCAL` を除く。

**GraphQL の Dataloader との共存**

- Bullet は、検出の状態をスレッド変数（`Thread#thread_variable_set`）に置く。graphql-ruby の Dataloader はソースを同じスレッドの別の Fiber で動かすので、ソースの中の読み込みも同じリクエストとして見える。`AsyncDataloader` を使わない（`graphql-schema.md`「ページングと N+1」）ので、スレッドは 1 つのままである。
- Bullet が見るのは、AR のレコードの関連の読み込みだけである。本デモの GraphQL の型は AR のレコードではなく公開 API の値を受け取るので、Bullet が見張るのは公開 API の中（値を組み立てるときの関連の読み込み）になる。フィールドが親ごとに公開 API を呼ぶ N+1 は関連の読み込みではないので、クエリ数の予算が落とす。

**判断**：N+1 の検出に Bullet を使うか、Rails の `strict_loading`（`:n_plus_one_only`）を使うか

- **既定の推奨**：Bullet をテストで使う。検出だけを行い、本番の挙動を変えない。
- **裏返る条件**：Bullet が Rails の版上げに追いつかない、または誤検知の許可リストが増え続ける → `TenantRecord` に `strict_loading_mode = :n_plus_one_only` を付ける。こちらは本番でも例外になるので、テストで網羅してから入れる。
- **撤退コスト**：小さい。gem と `spec/support/bullet.rb` を消すだけで済む。

**完了条件**

```sh
bundle exec rspec
bundle exec rspec spec/graphql/query_budget_spec.rb
```

公開 API の 1 つで先読み（`includes`）を外すと、その公開 API のテストが Bullet の例外で落ちることを、手で確かめる。リゾルバの 1 つで Dataloader を外し、親ごとに公開 API を呼ぶ形にすると、クエリ数の予算が落ちることも確かめる。

**実装する文書の節**：`graphql-schema.md`「ページングと N+1」、`decisions.md` 6 章（N+1 対策）

## M18 構造化ログと相関 ID

**目的**：障害の原因を、ログだけで辿れる。1 行のログが、どのリクエスト・テナント・ユーザー・GraphQL の操作・ジョブ・イベントのものかを持つ。発注側の発注から受注側の受注確定までのように、テナントをまたぐ一連の処理を、1 つの相関 ID で引ける。個人情報と秘密は書かない。

**作るもの**

- ログの出口：Rails 8.1 の `Rails.event`（`ActiveSupport::EventReporter`）を、ログの出口にする。Rails 8.1 は、コントローラ・ジョブ・Active Record の計装を、構造化イベント（`action_controller.request_completed`・`active_job.started`・`active_job.completed` など）として `Rails.event` に出す。イベントをログに書く購読者は付属しないので、`Platform::JsonLogSubscriber`（`packs/platform`）を `Rails.event.subscribe` で登録する。購読者は 1 件のイベントを 1 行の JSON（`name`・`payload`・`tags`・`context`・`timestamp`）にして、本番では標準出力に、開発とテストでは `log/events.log` に書く。
- フレームワークの文字列のログ：本番では、構造化イベントと同じ内容を書くフレームワークのログの購読（`ActionController::LogSubscriber` など）を外す。外す購読の一覧は、着手時に Rails 8.1.4 のソースで確かめる。残る `Rails.logger` の行は、JSON の書式（`Platform::JsonLogFormatter`）で、同じ文脈を付けて書く。
- 文脈：`Rails.event.set_context` で次の項目を設定する。Rails は文脈を、リクエストとジョブの前後で空に戻す。

  | 項目 | 設定する場所 |
  |---|---|
  | `request_id` | `GraphqlController`・`SessionsController`（`request.request_id`） |
  | `tenant_id`・`user_id` | `GraphqlController`（認証の後）、`ApplicationJob`（テナントを復元した後）。`Contracts::EventJob` は宛先テナント |
  | `graphql_operation` | `GraphqlController`（`operationName`。無ければ `anonymous`） |
  | `job_id`・`job_class`・`queue` | `ApplicationJob` の `around_perform` |
  | `event_id`・`event_name` | `Contracts::EventJob` |
  | `correlation_id`・`causation_id` | 下の「相関 ID と因果 ID」 |

  `GraphqlController` は、スキーマを実行する前に文脈を設定する。`Rails.event` の文脈は Fiber のストレージにあり、Dataloader が作る Fiber は、作られた時点の値を写して持つ。Fiber の中で設定した値は、親に戻らない。
- 相関 ID と因果 ID：
  - **相関 ID**（`correlation_id`）：一連の処理の始まりで 1 つ決め、最後まで同じ値を運ぶ。利用者のリクエストでは、`request_id` を相関 ID にする。
  - **因果 ID**（`causation_id`）：いまの処理を直接引き起こしたものの ID。リクエストでは空、イベントの受け手では届いたイベントの `event_id` である。
  - **イベントの付帯情報**：`Contracts.publish` は、イベントごとに `event_id`（UUIDv7）を作る。それと、いまの文脈の相関 ID・因果 ID、発行元のテナント ID、発行時刻（`published_at`）を、付帯情報としてジョブの引数に載せる。ペイロードには入れない。受け手のジョブは付帯情報から文脈を設定する。受け手の中で発行するイベントは、同じ相関 ID と、因果 ID として受け手が受け取ったイベントの `event_id` を持つ。
  - **イベント以外のジョブ**：`ApplicationJob` も、登録した時点の相関 ID を引数に載せ、実行時に文脈へ戻す。

  これで、発注側の `placePurchaseOrder` のリクエスト → 「発注登録」 → 受注側の ACL → 「受注確定」 → 購買の受け手、の全ログが同じ相関 ID を持つ。テナントは途中で変わるので、相関 ID でログを引けるのは運用者だけで、テナントの利用者には相手側のログを見せない。
- アプリが出すイベント：GraphQL の操作の終わりに `graphql.operation_completed`（操作名・結果の種類・ユーザーエラーのコード・時間）、受け手の終わりに `contracts.event_handled`（イベント名・受け手・配送の遅れ = 受け手の始まりの時刻 − `published_at`）。
- 書かないもの：
  - **個人情報と秘密**：メールアドレス・氏名・パスワード・セッションの Cookie・API キー・Webhook の署名。ペイロードには ID・コード・件数・時間だけを入れ、自由記述（取消の理由・在庫調整の理由）も入れない。
  - **GraphQL の変数とクエリの本文**：変数はキーの一覧だけを書き、クエリの本文は SHA-256 の要約だけを書く。
  - **SQL**：`active_record.sql` はデバッグのイベントで、開発でだけ出る。本番は出さない。
  - **ハッシュでないペイロード**：`Rails.event` は、ハッシュのペイロードにだけ `filter_parameters` を掛ける。購読者は、ハッシュでないペイロードを開発とテストで例外にする。`filter_parameters` に `name` を足すと `item_name`・`operation_name` まで消えるので、氏名は「ペイロードに入れない」規則で守る。
- `spec/contracts/correlation_spec.rb`：発注 → イベントを流す → 受注確定 → 購買の受け手、の全ログ行が同じ相関 ID を持ち、受け手の行の因果 ID が届いたイベントの `event_id` であることを確かめる。ログは、テストの中で購読者を足して集める。
- `spec/requests/log_hygiene_spec.rb`：ログインと、メールアドレス・パスワード・自由記述の理由を含む mutation を流し、集めたログ行のどこにもその値が現れないことを確かめる。

**判断**：ログの出口に `Rails.event` を使うか、lograge のような gem で文字列のログを JSON にするか

- **既定の推奨**：`Rails.event` を使う。Rails 8.1 の計装がそのまま構造化イベントになり、ハッシュのペイロードに `filter_parameters` が掛かり、文脈がリクエストとジョブの単位で空に戻る。メトリクス（M30）も同じイベントから作れる。
- **裏返る条件**：Rails の構造化イベントの名前やペイロードが版上げのたびに変わり、追従の手間がログの価値を上回る → 購読者に、名前を固定の一覧へ写す層を足す。それでも足りなければ、OpenTelemetry のログに移る。
- **撤退コスト**：小さい。購読者を外せば、Rails の文字列のログに戻る。高くつくのは、アプリのコードが `Rails.logger.info` の文字列に文脈を埋め込んだ後で、構造化に移ることである。

**完了条件**

```sh
bundle exec rspec spec/contracts/correlation_spec.rb spec/requests/log_hygiene_spec.rb spec/jobs
bin/rails runner 'Rails.event.notify("smoke.check", { n: 1 })' && tail -n 1 log/events.log | ruby -rjson -e 'JSON.parse(STDIN.read)'
```

`bin/jobs` を動かして発注を 1 件登録し、`grep <相関 ID> log/events.log` で 2 社の処理の行が並ぶことを、手で確かめる。

**実装する文書の節**：`decisions.md` 2 章（テナント文脈のログへの伝播）、`adr/005` 決定 3、`data-model.md`「イベントの受け口と冪等キー」の付帯情報

**文書に残すこと**：`adr/005` 決定 3 のジョブの引数の一覧に付帯情報を足す。外したフレームワークのログの購読と、ログの出力先を `guides/config.md` に書く。

## M19 監査ログ

**目的**：相手テナントに効果が及ぶ書き込みは、必ず監査ログに残る。記録は mutation の基底クラスとイベントのジョブの基底クラスが行い、個々の操作で手書きしない（`decisions.md` 2 章「監査」）。監査ログは追記だけで、書き換えも削除もできない。

`decisions.md` 2 章は「操作者のテナントとデータの所有テナントが異なる書き込み」を監査の対象にする。本デモには相手テナントの名義で書く経路が無い（`context-map.md`「テナントと所有」）ので、対象を「相手テナントに効果が及ぶ書き込み」に置き換える。相手テナントへのイベントを出す操作、相手から見えるデータ（カタログ・取引関係）を変える操作、相手の操作で自社のデータが変わったこと（イベントの受信）がこれに当たる。

**作るもの**

- 表 `audit_logs`（`packs/platform`）と、追記だけにする仕組み（`data-model.md`「監査ログ（`platform`）」）。
- mutation の宣言：`Mutations::BaseMutation` に `audit "<操作>", target: ..., counterparty: ...` か `audit_exempt reason:` を必須にする。宣言が無ければ、認可の宣言と同じく、開発とテストで例外、本番で拒否する。基底 mutation は、`perform` が成功の値を返したときだけ、同じトランザクションで 1 行を書く。ユーザーエラーとトップレベルのエラーでは書かない。どちらも書き込みが戻るので、記録も一緒に戻る。対象の mutation と例外の一覧は `graphql-schema.md`「監査ログ」に置く。
- イベントの受信：`Contracts::EventJob` が、受け手の `handle` を終えた後、同じトランザクションで `event.received` を 1 行書く。操作者は `system`、因果 ID は `event_id`、相手テナントは付帯情報の発行元のテナントである。同じイベントの 2 回目の配送では書かない（一意索引と `ON CONFLICT DO NOTHING`）。
- 列挙テスト：`spec/graphql/authorization_declarations_spec.rb` を広げ、全 mutation が監査の宣言を持ち、`audit_exempt` の一覧が `graphql-schema.md`「監査ログ」の表と一致することを確かめる。
- GraphQL：`viewer.auditLogs`（`admin` だけ。`graphql-schema.md`「監査ログ」）。到達可能性のテストに「`Viewer` からたどれる型は `shared` だけである」を足し、入口の行列に行を足す。
- 保存期間を過ぎた行の削除：所有ロールの rake タスク `audit:purge`。所有ロールの資格情報を持つ運用の工程で、月に 1 回流す。Web とワーカーには資格情報が無いので流せない。
- `spec/db/audit_logs_spec.rb`：アプリのロールの UPDATE と DELETE が権限で拒まれる。所有ロールでも、UPDATE と、保存期間の中の行の DELETE がトリガーで拒まれる。
- `spec/requests/audit_spec.rb`：`placePurchaseOrder` の成功で 1 行、`NOT_PERMITTED` で 0 行。受注側には、イベントの受信の 1 行ができ、同じイベントを 2 回流しても増えない。発注側の行と受注側の行が、同じ相関 ID を持つ。

**判断**：監査の記録をどこに置くか

- **既定の推奨**：mutation の基底クラスと、イベントのジョブの基底クラスの 2 か所に置く。本デモで書き込みが起きる入口は、この 2 つだけだからである。公開 API の操作には共通の基底クラスが無く、記録を置くと操作ごとに手書きになる。
- **裏返る条件**：GraphQL の mutation 以外の書き込みの入口（管理画面・外部向けの API・運用の手順のスクリプト）が増える → 公開 API の操作に宣言を移し、入口を問わず記録する。
- **撤退コスト**：中程度。宣言は mutation ごとに 1 行なので移すのは機械的だが、記録の粒度（mutation 単位か、公開 API の操作単位か）が変わり、移す前と後の行を並べにくくなる。

範囲外：相手テナントへの監査ログの写し（発注側が、受注側の受信の記録を見ること）、月ごとの表の分割。

**完了条件**

```sh
bundle exec rspec spec/db/audit_logs_spec.rb spec/requests/audit_spec.rb spec/graphql spec/matrix
```

**実装する文書の節**：`decisions.md` 2 章「監査」、`data-model.md`「監査ログ（`platform`）」、`graphql-schema.md`「監査ログ」

**文書に残すこと**：監査の対象を変えたら、`graphql-schema.md`「監査ログ」の表を同じ変更で直す。

## M20 GraphQL スキーマの破壊的変更の検出

**目的**：GraphQL のスキーマの変更が、PR の差分として読める。クライアントを壊す変更（フィールドの削除・型の変更・必須の引数の追加など）は、先に非推奨にしてからでないと CI を通らない（`graphql-schema.md`「スキーマの変更と非推奨」）。

**作るもの**

- `lib/tasks/graphql.rake`：`GraphQL::RakeTask.new(schema_name: "FactoryOpsSchema")`。`bin/rails graphql:schema:idl` が、リポジトリの根に `schema.graphql` を書く。
- `spec/graphql/schema_dump_spec.rb`：`FactoryOpsSchema.to_definition` が `schema.graphql` と一致することを確かめる。型を変えて書き直しを忘れると落ちる。
- graphql-schema_comparator を development と test のグループに入れる。
- `bin/check-schema-compat`：基準（環境変数 `BASE_REF`、既定は `origin/main`）の `schema.graphql` と、作業中の `schema.graphql` を `GraphQL::SchemaComparator.compare` で比べる。
  - 非破壊の変更と、危険な変更（enum の値の追加など）は、一覧を出すだけにする。
  - 破壊的変更は、次のどちらかに当たれば通し、どちらにも当たらなければ失敗する。
    1. 消えたフィールド・引数・enum の値が、基準のスキーマで `@deprecated` だった
    2. `docs/graphql/breaking-changes.yml` に、その変更（比較の結果の文言）と理由が書いてある
  - 結果を標準出力と `$GITHUB_STEP_SUMMARY` に書く。
- CI の lint のジョブで、`actions/checkout` を `fetch-depth: 0` にして基準を取れるようにし、`bin/check-schema-compat` を流す。

**判断**：比較に graphql-schema_comparator を使うか

- **既定の推奨**：使う。graphql-ruby の手引き（Testing の Schema structure）が挙げる Ruby の比較器で、依存する graphql の版の範囲に 2.6 が入る。
- **裏返る条件**：更新が止まったまま、graphql-ruby の 3 系で動かなくなる → Node の graphql-inspector を CI でだけ使うか、`GraphQL::Schema` の反射で要る検査（削除・型の変更・必須の追加）だけを自作する。
- **撤退コスト**：小さい。`bin/check-schema-compat` の中を差し替えるだけで済み、`schema.graphql` とその書き出しの検査は残る。

> graphql-schema_comparator の最新は 1.2.1（2023 年 10 月の公開）で、依存する graphql の版の範囲は `>= 1.10, < 3.0` である。

**完了条件**

```sh
bin/rails graphql:schema:idl && git diff --exit-code schema.graphql
bundle exec rspec spec/graphql/schema_dump_spec.rb
BASE_REF=origin/main bin/check-schema-compat
```

フィールドを 1 つ消した一時の変更で `bin/check-schema-compat` が失敗し、基準の側でそのフィールドに `deprecation_reason` を付けると通ることを、手で確かめる。

**実装する文書の節**：`graphql-schema.md`「スキーマの変更と非推奨」、`adr/004`

## M21 取消依頼と審査

**目的**：発注側の取消は、受注側の承認でだけ成立する。審査中は出荷の指示と計上が止まる。

**作るもの**：`cancellation_requests`・`cancellation_reviews`・`shipping_holds`、取消依頼・出荷停止・出荷停止解除・取消承認・取消却下・出荷取消のイベント、出荷済みの受注への取消依頼の自動却下、`requestPurchaseOrderCancellation`・`approveCancellationReview`・`rejectCancellationReview`、受注と発注の状況の「取消審査中」「取消依頼中」

**完了条件**：依頼 → 停止 → 承認 → 発注が「取消済み」・出荷依頼が「取消済」の通しのテスト。依頼 → 却下 → 発注が元の状況に戻る通しのテスト。審査中の出荷の計上が拒否されるテスト。

**実装する文書の節**：`context-map.md`「取消の流れ」1〜4、`data-model.md`「出荷（`fulfillment`）」の出荷停止

## M22 受注側の取消と、取消と出荷の競合

**目的**：受注側は審査なしで取り消せる。同時に進んだ取消と出荷計上は、引当の行ロックでどちらか一方だけが成立する。

**作るもの**：`Sales::OrderCancellation.cancel`、受注取消のイベントと購買の受け手（`supplier_cancelled_at`）、`cancelSalesOrder`

**完了条件**：`spec/concurrency/cancel_vs_ship_spec.rb`（重要シナリオ S4 の取消）：2 つの接続で取消と計上を同時に走らせ、どちらか一方だけが成立することを繰り返して確かめる。このテストはトランザクションで包まない設定で動かし、作った行を後で消す。

**実装する文書の節**：`context-map.md`「取消の流れ」の受注側の取消、`data-model.md`「取消と出荷の競合を止める場所」

## M23 検収

**目的**：検収数量は出荷数量を超えない。検収は入荷 1 件に 1 回で、受注側へ 1 回だけ届く。

**作るもの**：`receipt_inspections`・明細、`inspection_records`、`Purchasing::ReceiptInspection.record`、検収完了と請求対象確定のイベント（請求対象確定の受け手は M24）、受注の「検収済」、`inspectInboundShipment`、`InboundShipment.inspection`・`InboundShipmentLine.acceptedQuantity`

**完了条件**：出荷数量を超える検収が `INVALID_INPUT` になるテスト。すべての出荷実績が検収されたときだけ受注が「検収済」になるテスト。

**実装する文書の節**：`context-map.md`「検収と請求の流れ」1〜3、`data-model.md`「購買」「受注」の検収の表

## M24 請求の締め

**目的**：締めは取引先ごとに直列になる。消費税は請求書・税率ごとに 1 回だけ切り捨てる。前の期間の遅れた検収も次の締めで拾う。

**作るもの**：`billing_terms`・`billable_items`・`invoices`・`invoice_tax_summaries`、請求対象確定の受け手、`Billing::Terms`・`Billing::BillableItems`・`Billing::Closing.close`・`discard`、`supplier.billingTerms`・`supplier.billableItems`・`supplier.invoices`・`supplier.invoice`、`setBillingTerm`・`closeBillingPeriod`・`discardDraftInvoice`

**完了条件**：税率 8% と 10% が混ざる明細で、税額が明細ごとの丸めの合計と異なる例を含むテスト。末日締め（31）のテスト。下書きの破棄で明細が未請求に戻るテスト。

**実装する文書の節**：`data-model.md`「請求（`billing`）」、`context-map.md`「検収と請求の流れ」4・5 と請求書の組み立ての規則

## M25 請求書の発行と受領請求書

**目的**：確定した請求書と明細は変わらない。写しは発注側の名義で 1 回だけ作られる。

**作るもの**：`Billing::Closing.issue`、請求書発行のイベント、購買の受け手（`received_invoices`・明細）、`Purchasing::ReceivedInvoices`、`issueInvoice`、`buyer.receivedInvoices`・`buyer.receivedInvoice`

**完了条件**：確定後の変更が拒否されるテスト。同じ請求書発行を 2 回流しても写しが 1 件のテスト。`total = subtotal + tax_total` の CHECK 制約のテスト。重要シナリオ S5（`spec/scenarios/billing_amounts_spec.rb`）が通る。

**実装する文書の節**：`context-map.md`「検収と請求の流れ」5・6、`data-model.md`「購買」の受領請求書

## M26 ダッシュボードと失効の通し試験

**目的**：取引関係を失効させると 3 つの読む経路と新しい発注が閉じ、連結済みの取引はイベントで請求まで進む。この見せどころを 1 本のテストで示す。

**作るもの**

- `supplier.dashboard`（`graphql-schema.md`「読み取りの一覧」の 4 つの公開 API）
- `spec/scenarios/revocation_spec.rb`（重要シナリオ S2）：発注 → 受注確定 → 失効 → 経路 1〜3 が空・新しい発注が `NOT_PERMITTED` → 引当・出荷・検収・締め・発行がそのまま進み、発注側に受領請求書が届く
- 画面の問い合わせごとの複雑度のテスト（`graphql-schema.md`「ページングと N+1」）。問い合わせは、M17 の画面の問い合わせの一覧から読む

**完了条件**：上の 2 つのテストが通る。全マイルストーンの共通の完了条件が通る。

**実装する文書の節**：`context-map.md`「取引関係の失効」「テナントと所有」、`showcase.md`「1. テナントの境界：読む 3 経路、書けないこと、失効」

---

## 見せどころを足すマイルストーンに共通すること

M27〜M31 は、業務の流れを一通り作った後に、設計判断を見せる仕組みを足す。どれも、業務機能のマイルストーンに共通すること（表・公開 API・行列テスト・監査の宣言・`schema.graphql`）にも従う。範囲を広げすぎないよう、各節の「範囲外」に挙げたものは作らない。

## M27 販売単価のバイテンポラル履歴

**目的**：販売単価を、有効期間と記録期間の 2 つの時間軸で持つ（`adr/006`）。受注側は単価の改定を前もって登録でき、入力の誤りを過去の行を書き換えずに訂正できる。発行済みの請求書について、「発行の時点で信じていた単価」と「いま分かっている単価」を示せる。

**作るもの**

- マイグレーション：
  - 拡張 `btree_gist`、表 `item_prices`（`create_tenant_table`、品目へ `add_tenant_reference`）、現在の行の排他制約、書き換えを拒むトリガー、経路 1 の `partner_read`（`data-model.md`「受注（`sales`）」「RLS」）
  - 既存の `items.unit_price` を、有効期間が `(,)` で記録期間がマイグレーションの時刻から始まる行に写す。`items.unit_price` は、先に `ignored_columns` に入れてから、次のマイグレーションで消す（strong_migrations の手順）
  - `sales_order_lines.priced_on`：照合前は空で、照合で単価と一緒に埋まる。既存の行は受注日で埋める
- 公開 API `Sales::ItemPrices`：`schedule`・`correct`・`price_at`・`history`（品目ごとの全行）・`explain(actor, sales_order_line_ids, as_of:)`。
- 単価を使う箇所の切り替え（`adr/006` 決定 5）：`Sales::Catalog`・`Sales::PublishedCatalog` は今日の単価を返す。ACL（`Sales::PurchaseOrderTranslator`）と照合のやり直し（`Sales::PartMappings.register`）は、受注日の単価を写し、`priced_on` を書く。`saveItem` の `unitPrice` は、品目を作るときは有効期間 `(,)` の行を作り、既存の品目で値が変わるときは今日からの改定として予約する。
- GraphQL：`Item.prices`・`ItemPrice`・`scheduleItemPrice`・`correctItemPrice`・`BillableItem.priceExplanation`（`graphql-schema.md`「受注側の視点」「mutation の一覧」）。`scheduleItemPrice`・`correctItemPrice` は、発注側のカタログに見える単価を変えるので監査する。
- 行列テスト：`item_prices` の行（`granted_buyer` は公開品目の現在の行を読める）と、新しいフィールドと mutation の行。
- テスト：
  - 単体（`packs/sales/spec/public/sales/item_prices_spec.rb`）：予約・訂正・`price_at` を、有効日 × 記録時点の表で確かめる。予約を同じ有効日で 2 回流しても行が増えない。
  - DB（`packs/sales/spec/db/item_prices_constraints_spec.rb`）：現在の行同士の有効期間の重なりを排他制約が拒み、記録期間を閉じる以外の UPDATE と DELETE をトリガーが拒む。
  - 結合：改定日の前日と当日の発注で、受注明細の単価が切り替わる。請求書の発行の後に単価を訂正すると、`priceExplanation` が発行時の単価と訂正後の単価を別々に返す。

**完了条件**

```sh
bin/check-structure   # btree_gist と排他制約が、migrate と load の両経路で structure.sql と一致する
bundle exec rspec packs/sales/spec spec/matrix spec/requests/item_prices_spec.rb
```

**範囲外**：得意先別の単価と数量割引、発注側への改定予定の公開、訂正の承認の手順（`adr/006`「見直す条件」）。

**実装する文書の節**：`adr/006`、`data-model.md`「受注（`sales`）」の `item_prices`・「RLS」の経路 1、`graphql-schema.md`「受注側の視点」

**文書に残すこと**：`adr/006` のステータスに、実装を終えたことを書く。

## M28 外部サービスの呼び出しと非同期の型

**目的**：`adr/007` の非同期処理の型のうち、確実な外部送信（A-2）・撃ちっぱなし（B-1）・inbox（A-3）を、SendGrid のメールの送信と配信結果の受信で実装する。外部への作用は 1 つの登録口からだけ登録され、429 の待ち時間に従って再試行し、失敗を運用者に知らせる。テストと開発では、本物の SendGrid を呼べない。

**作るもの**

- パッケージ `packs/notifications`（`Notifications::`）。依存先は `platform`・`partnerships`（宛先のメールアドレスを自社の `users` から引く）。`sales`・`purchasing` の依存先に `notifications` を足す（`context-map.md`「疎結合を守る規則」）。表は `email_deliveries` と `webhook_inbox_events`（`data-model.md`「通知（`notifications`）」）。
- `ExternalEffectJob`（`packs/platform`）と、`Notifications::CriticalDeliveryJob`・`BestEffortMailJob`・`ProcessInboxJob`（`adr/007` 決定 4〜6）。
- 公開 API `Notifications::Email.deliver_critical`・`deliver_best_effort` と、通知の種類の登録 `Notifications::Catalog`。種類は 2 つにする。
  - `received_invoice`（確実）：購買の「請求書発行」の受け手が、受領請求書を書くのと同じトランザクションで、自社の `admin` へ送る。
  - `new_sales_order`（撃ちっぱなし）：受注側の ACL が受注を確定したときに、自社の担当者へ送る。
- メールの本文は Action Mailer のテンプレート（`Notifications::Mailer`、text だけ）で書き、送信はジョブの中で `deliver_now` を呼ぶ。
- 送信先の切り替え：`Notifications::Provider` の実装を 3 つ置き、`config.x.notifications.provider` で選ぶ。
  - `Sendgrid`：v3 の送信 API を `Net::HTTP` で呼ぶ。API キーは credentials に置き、ログに書かない。本番以外の環境では、SendGrid の sandbox mode（受け付けの検査だけを行い、配信しない）を有効にしないと起動時に例外にする。
  - `FileSystem`（開発）：`tmp/mails/` に 1 通 1 ファイルで書く。
  - `Fake`（テスト）：メモリに積み、テストから読める。
- WebMock を test のグループに入れ、`spec/spec_helper.rb` で全テストに `WebMock.disable_net_connect!(allow_localhost: true)` を掛ける。
- Webhook：`Webhooks::SendgridEventsController`（ルートパッケージ）と `POST /webhooks/sendgrid/events`。セッションを使わず、署名で認証する（`adr/007` 決定 5 の A-3）。
- キューの設定：`config/queue.yml` を `adr/007` 決定 7 の 4 つのワーカーに分け、`Contracts::EventJob` を `events` に載せる。定期のジョブ（`config/recurring.yml`）に、inbox の未処理を拾う（毎分）と処理済みを消す（毎日）を足す。
- カスタム Cop `FactoryOps/ExternalEffectEnqueue` と、`spec/notifications/call_sites_spec.rb`（`adr/007` 決定 4）。
- 再送の操作 `Notifications::Email.redeliver_failed(since:)`：再試行を使い切った確実な送信の `failed_at` を空に戻し、同じ送信記録のジョブを登録し直す。新しい送信記録は作らない。運用者は rake タスク `notifications:redeliver` から呼び、タスクはテナントを明示して 1 つずつ回る（`decisions.md` 2 章）。
- ガードテスト：`spec/jobs/event_job_atomicity_spec.rb` を広げ、`enqueue_after_transaction_commit` が `false` のクラスが `Contracts::EventJob` と `Notifications::CriticalDeliveryJob` の 2 つだけであることと、`ExternalEffectJob` のどのサブクラスもその値と保証を自分のクラスで宣言していることを確かめる。
- テスト：
  - `Sendgrid` のアダプタ：WebMock のスタブで 202・429（待ち時間のヘッダ付き）・500・400・401・タイムアウトを返し、`adr/007` 決定 5 の A-2 の表のとおりに分類される。
  - 確実な送信：同じ「請求書発行」を 2 回流しても送信記録は 1 件。`issueInvoice` が戻れば、送信記録もジョブも残らない。受け付けの後にジョブをもう一度流しても、送らない。400 と、再試行を使い切ったときに `failed_at` が入り、`notification.delivery_failed` が出る。
  - inbox：同じ `sg_event_id` の 2 回の受信で行が 1 件。署名の誤りで 401。保存した行にメールアドレスが無い。処理を 2 回流しても、送信記録の時刻列が 1 回だけ書かれる。

**完了条件**

```sh
bundle exec rspec packs/notifications/spec spec/notifications spec/jobs spec/requests/sendgrid_webhook_spec.rb spec/rubocop
bin/rubocop
```

`bin/jobs` を動かして請求書を発行し、`tmp/mails/` に受領請求書の通知が 1 通できることを、手で確かめる。

**範囲外**：HTML のメール、配信停止の管理、通知の設定画面と宛先の選択、提供元の単位で送信を止める仕組み（`adr/007`「見直す条件」）。

**実装する文書の節**：`adr/007`、`decisions.md` 5 章、`data-model.md`「通知（`notifications`）」、`context-map.md`「コンテキスト」

**文書に残すこと**：`adr/007` の未確認の事項を、確かめた結果で置き換える。

## M29 大量データの取り込み

**目的**：受注側が、品目と単価、在庫の CSV（数万行）を取り込める。取り込みは、イベントの配送とメールを待たせない。途中で止まっても続きから再開し、失敗した行を報告し、進み具合を GraphQL で見せる。メモリの使用量は、ファイルの大きさの上限とチャンクの大きさで上から抑える。

**作るもの**

- パッケージ `packs/imports`（`Imports::`）。依存先は `platform`・`partnerships`・`sales`・`inventory`。表は `imports`・`import_files`・`import_rows`（`data-model.md`「取り込み（`imports`）」）。
- ファイルの受け取り：`POST /imports/files`（`ImportFilesController`、ルートパッケージ）が `multipart/form-data` の CSV を受け取り、`import_files` に書いて ID を返す。ファイルを置くだけで、業務の表には何も起きない。10 MB を超えるファイルは受け付けない。セッションで認証し、`Origin` ヘッダが許可した origin と一致しなければ拒む。`GraphqlController` の `application/json` の制限に代わる CSRF 対策である。
- 取り込みの開始：mutation `startImport(fileId, kind)` が `imports` の行を書き、ジョブを登録する。業務の表に効果が及ぶのはここからなので、監査はこの mutation の宣言で行う。
- ジョブ `Imports::RunJob`（`adr/007` 決定 5 の A-4）：`ApplicationJob` を継承し、`ActiveJob::Continuable` を取り込む。`queue_as :imports`、`limits_concurrency to: 1, key: ->(import_id, tenant_id) { tenant_id }`、`tenant_transaction :per_chunk`。
  1. `step :stage`：`import_files.content` を `CSV.new` で 1 行ずつ読み、1,000 行ごとに `import_rows` へ `insert_all` で書く。カーソルは書き終えた行番号である。見出しの行の誤りと、50,000 行を超えるファイルは、取り込み全体の失敗（`failed_at`）にする。
  2. `step :apply`：`import_rows` を行番号の順に 500 行ずつ取り、チャンクごとに `Tenancy.with_tenant` を開いて反映する。行ごとに `applied_at` か `error` を書き、`imports` の件数を足す。`applied_at` のある行は飛ばす。カーソルは反映したチャンクの最後の行番号である。
  3. `step :finalize`：`finished_at` を書き、`import_files` の中身を消す。
- 反映の書き方（種類ごと）：
  - **品目**：品目の列（コード・名前・単位・税率・公開）は、公開 API `Sales::Catalog.bulk_upsert` が `upsert_all(unique_by: [:owner_tenant_id, :code])` で書く。`owner_tenant_id` には `Current.tenant_id` を明示して入れ、RLS の `WITH CHECK` が他社の名義の行を拒む。単価の列（単価・有効日）は、行ごとに `Sales::ItemPrices.schedule` を呼ぶ（`adr/006` 決定 3）。
  - **在庫**：行ごとに `Inventory::Adjustment` を呼び、目標の数量との差を入庫か出庫にする。`stocks` を `insert_all` で書かない。在庫の変更は `move!` を通って移動履歴を残す（`data-model.md`「在庫（`inventory`）」）。
  - `insert_all`・`upsert_all` は、モデルのコールバックとバリデーションを通らない。使ってよいのは、不変条件が DB の制約だけで閉じる表（品目・置き場の行）に限る。
- 冪等：同じチャンクを 2 回反映しても結果が 1 つになる。`applied_at` のある行を飛ばし、品目の upsert と単価の予約（同じ単価・同じ有効日なら何もしない）は、もう一度流しても変わらない。プロセスが落ちて中断点を通らなかったときに、最後に保存したカーソルからやり直すためである。
- GraphQL：`supplier.imports`・`supplier.import(id)`・`Import`・`startImport`（`graphql-schema.md`「受注側の視点」）。
- 再登録の操作 `Imports::Runs.reenqueue(import_id)`：ジョブを失って「待機中」のまま残った取り込みのジョブを登録し直す。運用者は rake タスク `imports:reenqueue` から呼ぶ。
- `bin/rails imports:sample[50000]`：試験用の CSV を作る。
- テスト：
  - 中断と再開：アダプタの `stopping?` を `stage` の途中と `apply` の途中で真にして中断させ、もう一度流すと続きから進み、全行が 1 回ずつ反映される。
  - 部分失敗：3 行のうち 1 行が不正なファイルで、反映が 2 行・失敗が 1 行・状況が `PARTIALLY_FAILED` になる。
  - テナント：`upsert_all` に他社の `owner_tenant_id` の行を混ぜると、RLS が拒む。
  - キュー：`config/queue.yml` を読み、`imports` のワーカーが他のキューを持たず、`events` のワーカーが `imports` を持たないことを確かめる。

**判断**：失敗した行があるとき、残りの行を反映するか

- **既定の推奨**：行ごとに独立に反映し、失敗した行だけを報告する。品目と在庫の行は互いに依存しない。9 割が正しいファイルを丸ごと捨てると、利用者は直した 1 割と一緒に全部を送り直すことになる。
- **裏返る条件**：行が互いに依存する（親の品目と子の行を同じファイルで送る）か、利用者が「全部か無しか」を求める → 数万行を 1 つのトランザクションにはできない（中断点を置けない）ので、置き場で全行を検証してから反映する 2 段にし、検証で 1 行でも落ちたら反映しない。
- **撤退コスト**：小さい。置き場の行と行ごとのエラーは、どちらの方式にも要る。

**判断**：ファイルを DB に置くか、オブジェクトストレージに置くか

- **既定の推奨**：`import_files.content`（`bytea`）に置く。テナントの表なので RLS が掛かる。Active Storage を使うと、その表（`active_storage_blobs` など）にテナント列と RLS を足すことになる。
- **裏返る条件**：ファイルの上限を 10 MB より大きくする → オブジェクトストレージに置き、鍵だけを `import_files` に持つ。読み出しはストレージから 1 行ずつにする。
- **撤退コスト**：小さい。置き場を読む箇所は `stage` の 1 か所である。

**完了条件**

```sh
bundle exec rspec packs/imports/spec spec/requests/imports_spec.rb spec/jobs
```

50,000 行の CSV を取り込み、ワーカーの常駐メモリ（`ps -o rss`）の増分が 100 MB 以内で、`supplier.import` の件数が進むのを、手で確かめる。途中で `bin/jobs` を止めて起動し直し、続きから進むことも確かめる。

**範囲外**：取り込みの取消、失敗した行だけのやり直し（利用者は失敗した行を直したファイルを送り直す）、Excel の形式、受注・発注の取り込み。

**実装する文書の節**：`adr/007` 決定 5 の A-4・決定 7、`adr/006` 決定 3、`data-model.md`「取り込み（`imports`）」「在庫（`inventory`）」

## M30 メトリクス

**目的**：GraphQL の操作の時間、キューの滞留と待ち時間、イベントの配送の遅れ、外部の呼び出しの失敗と 429、取り込みの速さを、数値で測れる。メトリクスのラベルに、テナントとユーザーを入れない。

**作るもの**

- `yabeda`・`yabeda-prometheus`。メトリクスの定義は `config/initializers/metrics.rb` の 1 か所に置く。
- 値の出どころは、M18 の `Rails.event` の購読者 `Platform::MetricsSubscriber` の 1 つにする。キューの滞留だけは、収集の時点で Solid Queue の表を数える。

  | メトリクス | 種類 | ラベル | 出どころ |
  |---|---|---|---|
  | `graphql_operation_duration_seconds` | ヒストグラム | `operation`・`outcome`（`ok`・`user_error`・`error`） | `graphql.operation_completed` |
  | `graphql_top_level_errors_total` | カウンタ | `operation`・`code` | 同上 |
  | `job_duration_seconds` | ヒストグラム | `queue`・`job_class` | `active_job.completed` |
  | `job_queue_latency_seconds` | ヒストグラム | `queue` | `active_job.started`（始まりの時刻 − `enqueued_at`） |
  | `event_delivery_lag_seconds` | ヒストグラム | `event` | `contracts.event_handled` |
  | `queue_ready_jobs`・`queue_blocked_jobs`・`queue_failed_jobs` | ゲージ | `queue` | 収集の時点で `solid_queue_ready_executions`・`solid_queue_blocked_executions`・`solid_queue_failed_executions` を数える |
  | `external_requests_total` | カウンタ | `provider`・`status`（`2xx`・`429`・`4xx`・`5xx`・`timeout`） | `notifications.provider_responded` |
  | `notification_acceptance_seconds` | ヒストグラム | `kind` | `notification.accepted`（受け付けの時刻 − 送信記録の作成時刻） |
  | `notification_failures_total` | カウンタ | `kind`・`reason` | `notification.delivery_failed` |
  | `import_rows_total` | カウンタ | `kind`・`result`（`applied`・`failed`） | `imports.chunk_applied` |
  | `import_duration_seconds` | ヒストグラム | `kind`・`size`（10,000 行以下は `small`、超えれば `large`） | `imports.finished` |

- ラベルの規則：テナント ID・ユーザー ID・伝票の ID をラベルにしない。値の種類が増え続けて保存が膨らみ、メトリクスの基盤にテナントの情報が流れるからである。テナントごとの調査は、ログ（相関 ID）で行う。`operation` には、クライアントが自由に付ける `operationName` をそのまま使わない。`config/graphql_operations.yml` に登録した名前だけを使い、それ以外は `other` にする。登録した名前が、M17 の画面の問い合わせの一覧の操作名と一致することを、テストで確かめる。
- 公開の仕方：`yabeda-prometheus` の exporter を、Web とワーカーのプロセスでそれぞれ別のポート（9394・9395）で立てる。ポートは内部のネットワークにだけ開き、公開のロードバランサーに出さない。Rails のルートには `/metrics` を置かない。Puma を複数のプロセスで動かすときは、prometheus-client の `DirectFileStore` を使う。
- `spec/platform/metrics_subscriber_spec.rb`：構造化イベントごとに、対応するメトリクスが増える。登録していない `operationName` は `other` になる。定義したすべてのメトリクスのラベルに、`tenant`・`user`・`_id` で終わる名前が無い。

**判断**：Yabeda と Prometheus にするか、OpenTelemetry にするか

- **既定の推奨**：Yabeda と Prometheus にする。メトリクスを 1 か所の Ruby の定義から出し、Prometheus が引きに来る形なので、収集器（Collector）を立てずに手元とデモで確かめられる。OpenTelemetry の Ruby のメトリクスの SDK は、まだ安定版でない。
- **裏返る条件**：分散トレースが要る（別のサービスが増える）か、組織の監視基盤が OTLP で受ける → OpenTelemetry に移る。
- **撤退コスト**：小さい。値の出どころは `Rails.event` の購読者の 1 つなので、出口のライブラリを替えるだけで済む。

> opentelemetry-metrics-sdk の最新は 0.20.0 で、1.0 に達していない（2026 年 10 月に rubygems.org で確かめた）。

**完了条件**

```sh
bundle exec rspec spec/platform/metrics_subscriber_spec.rb
```

`bin/rails server` で GraphQL の問い合わせを 1 回流し、`curl -s localhost:9394/metrics | grep graphql_operation_duration_seconds_bucket` に値が出ることを、手で確かめる。

**範囲外**：分散トレース、ダッシュボードの定義、ログの集約基盤。

**実装する文書の節**：M18 の構造化イベント、`adr/007` 決定 7（キュー）

**文書に残すこと**：exporter のポートとネットワークの制限を `guides/config.md` に書く。

## M31 SLO と障害対応の手順書

**目的**：主な操作に SLO を決め、M30 のメトリクスで測り、外れそうなときに警報を出す。主な障害には手順書があり、どの警報からも手順書へたどれる。

**作るもの**

- SLO（`docs/slo.md`）。値は初めの目安で、30 日の実測の後に見直す。

  | SLI | 測り方（M30 のメトリクス） | SLO（28 日） |
  |---|---|---|
  | 発注の登録の速さ | `placePurchaseOrder` の `graphql_operation_duration_seconds` が 500 ms 以内の割合 | 95% |
  | 発注の登録の成功 | 同じ操作で `outcome` が `error` でない割合 | 99.5% |
  | 画面の問い合わせの速さ | 登録した問い合わせが 1 秒以内の割合 | 95% |
  | イベントの配送の遅れ | `event_delivery_lag_seconds` が 60 秒以内の割合 | 99% |
  | 確実な通知の受け付け | `notification_acceptance_seconds{kind="received_invoice"}` が 15 分以内の割合 | 99% |
  | 取り込みの完了 | `import_duration_seconds{size="small"}` が 5 分以内の割合 | 95% |

- 警報の規則（`config/prometheus/alerts.yml`）：
  - **誤差の予算の消費**：SLO ごとに、1 時間で予算の 2% を消費する速さ（14.4 倍）で呼び出し、6 時間で 5%（6 倍）でチケットにする。
  - **状態の警報**：`queue_failed_jobs` が 10 分続けて 0 より大きい。`queue_ready_jobs{queue="events"}` が 5 分続けて 1,000 を超える。`notification_failures_total{kind="received_invoice"}` が増えた。`external_requests_total{status="429"}` の割合が 10 分続けて 20% を超える。`graphql_top_level_errors_total{code="FORBIDDEN"}` が増えた（scope と規則の食い違いで、テナントの境界の不具合の兆し）。実行中の取り込みで、`import_rows_total` が 15 分増えない。
  - どの警報も `annotations.runbook` に手順書のパスを持つ。
- 警報の規則のテスト（`config/prometheus/alerts_test.yml`）：`promtool test rules` で、イベントのキューの滞留と、確実な通知の失敗の 2 つの警報が、条件を満たした系列で発火することを確かめる。
- 手順書（`docs/runbooks/`）：各手順書は「警報 → 確かめること（流すコマンド）→ 止血 → 復旧 → 事後にすること」の順に書く。

  | 手順書 | 障害 | 止血と復旧の要点 |
  |---|---|---|
  | `queue-backlog.md` | キューが詰まる | キューごとの滞留と失敗を数え、ワーカーのプロセスを確かめる。`imports` のキューを止めて（`SolidQueue::Queue.find_by_name("imports").pause`）`events` を先に流す。原因を直してから、失敗したジョブをやり直す。受け手は冪等なので、やり直してよい |
  | `sendgrid-outage.md` | SendGrid の障害・429 の連続 | 応答の種類の内訳を見る。401・403 なら API キーを確かめる。429 が続けば `external_mail` のキューを止め、同時実行の上限を下げてから再開する。再試行を使い切った確実な通知は、`notifications:redeliver` で送り直す |
  | `import-stuck.md` | 取り込みが進まない | 取り込みの行の状況と、ジョブの有無を見る。ジョブを失った「待機中」の取り込みは、`imports:reenqueue` で登録し直す。中断を繰り返していれば、取り込みの ID でログを引く |
  | `rls-misconfiguration.md` | RLS の設定の誤りが疑われる | アプリの接続のロール（`pg_stat_activity`）、ロールの属性（`rolbypassrls`・`rolsuper`）、`relforcerowsecurity` とポリシーを `structure.sql` と比べる。疑いが消えるまで、メンテナンスの切り替え（環境変数 `MAINTENANCE_MODE`）で GraphQL を 503 にする。影響を受けたテナントは、監査ログとログの相関 ID で洗い出す |

- メンテナンスの切り替え：`MAINTENANCE_MODE` が立っていれば、`GraphqlController` は実行せずに 503 を返す。
- `spec/platform/alerts_runbook_spec.rb`：`alerts.yml` のどの警報も `runbook` を持ち、そのファイルが `docs/runbooks/` にあることを確かめる。

**完了条件**

```sh
docker run --rm -v "$PWD/config/prometheus:/rules" --entrypoint promtool prom/prometheus check rules /rules/alerts.yml
docker run --rm -v "$PWD/config/prometheus:/rules" --entrypoint promtool prom/prometheus test rules /rules/alerts_test.yml
bundle exec rspec spec/platform/alerts_runbook_spec.rb
```

CI にも、`promtool` の 2 つの検査を足す。各手順書の「確かめること」のコマンドを、開発環境で 1 回ずつ流して動くことを、手で確かめる。

**範囲外**：オンコールの当番表、外部の死活監視、ステータスページ。

**実装する文書の節**：M30 のメトリクス、`adr/007`（キューと送信の失敗）、`data-model.md`「RLS」

**文書に残すこと**：SLO を見直したら `docs/slo.md` と `alerts.yml` を同じ変更で直す。

---

## M32 シードデータ

**目的**：デモを開いた人が、両方の視点と 3 つの読む経路をすぐ見られる。

**作るもの**：`db/seeds.rb`。受注側に青嵐精機工業、発注側に架空の組立メーカー 2 社（全権限の付与あり・失効済み）を作る。factory-ops-demo の品目と得意先を写し、受注・出荷・検収・請求書まで進んだ取引と途中の取引を混ぜる。品目には、単価の改定の予約と訂正を 1 件ずつ含める。取り込みも 1 件（一部の行が失敗したもの）含める。シードは公開 API とイベントを通して作り、表へ直接書かない。

**完了条件**：`bin/rails db:reset` が通り、両社のユーザーでログインして `buyer`・`supplier` の主な問い合わせが値を返す。

## M33 フロントエンド

**目的**：姉妹プロジェクト factory-ops-demo の `frontend/`（以下、流用元）の Next.js を写し、画面部品をそのまま使い、データ取得層を REST から GraphQL へ書き換え、発注側の画面を足す。読み手が、受注側と発注側の両方の画面で、取引関係・失効・取消・検収・請求が動くのを見られるようにする。計画は済んでおり、実装は M32 の後に行う。

本節の用語は次のとおりである。**受注側**は GraphQL の `supplier` の視点（自社が受けた受注・在庫・出荷・請求を扱う）、**発注側**は `buyer` の視点（自社の発注と、相手を読む 3 経路を扱う）を指す。**画面**は Next のルート 1 つを指す。**入口**は GraphQL のルートのフィールド `viewer`・`buyer`・`supplier` を指す（`graphql-schema.md`「視点ごとに型を分ける」）。**画面の問い合わせ**は、画面が送る query と mutation の文書を指す（M17 の同名の一覧と同じもの）。

担当者は、次の順に決めて作る。まず、流用元を本リポジトリのどこへ写すかを決める（置き場所）。次に、写した画面と足す画面が、どの入口を呼び、それがどのマイルストーンでそろうかを確かめる（画面の一覧）。そのうえで、画面の部品はそのままに、REST の呼び出しを GraphQL の呼び出しに替える（データ取得層）。最後に、それを流用元の E2E の規則と本リポジトリの CI で守る（テストとゲート）。各段の「判断」は担当者が既定のとおりに進めてよいもので、作者に確かめるものは末尾の「著者判断」にまとめた。

**作るもの 1：置き場所**

- 流用元の main（`958de71`）の `frontend/` を、本リポジトリの `frontend/` に写す。git の履歴は持ち込まず、写した commit を commit メッセージに書く。
- 写さないもの：Cloudflare への配置（`wrangler.jsonc`・`open-next.config.ts`・`@opennextjs/cloudflare`・`wrangler`）、訪問者ごとのデモの開始・サンプル表示・混雑の通知（`lib/start-demo.ts`・`demo-session.ts`・`demo-state.ts`・`sample.ts`・`sample-data.json`・`components/demo-notice.tsx` と、それを分岐に使う箇所）、REST のスタブ（`e2e/stub-api.mjs`）と Go の API を起こす `e2e/start-api.sh`。
- Ruby の検査から外す：`.rubocop.yml` の `AllCops.Exclude`、`packwerk.yml` の `exclude`、`.dockerignore` に `frontend/` を足す。`.github/dependabot.yml` に `frontend/` の npm を足す。
- コードのコメント：写す担当者は、流用元の仕様・タスク・台帳の番号を指すコメント（`T-34`・`仕様 §7`・`正本 N-5`・`OI-45` の類）を、いまの振る舞いと理由に書き直すか消す。`guides/comments.md` の対象に `frontend/` を足し、`frontend/scripts/check-comments.mjs` が、これらの番号とマイルストーンの番号を含むコメントを落とす。`npm run lint` から呼ぶ。

**判断**：流用元をどこに置くか

- **既定の推奨**：本リポジトリの `frontend/` に写す。`schema.graphql` と画面の問い合わせが同じ commit で変わり、同じ CI で型検査される。非推奨を経ないスキーマの変更（M20）も、フロントエンドの型検査として同じ PR で落ちる。
- **裏返る条件**：流用元と本デモの両方で、画面部品をこれからも育てる → 部品を npm のパッケージに切り出し、両方から読む。
- **撤退コスト**：中。`frontend/` を別のリポジトリへ移すと、`schema.graphql` を取りに行く手順と、画面の問い合わせの一致を確かめる検査が要る。

**作るもの 2：画面の一覧**

画面の URL は視点で分け、受注側を `/supplier/...`、発注側を `/buyer/...` に置く。サイドバーは「受注側」「発注側」の 2 つのグループを持つ（著者判断 4）。表の「作るマイルストーン」は、画面が呼ぶ入口のフィールドと mutation を作るマイルストーンである。M15 以降のマイルストーンに依存する画面には ※ を付けた。

| | 画面 | 視点 | 流用元の画面 | 呼ぶ入口のフィールドと mutation | 作るマイルストーン |
|---|---|---|---|---|---|
| 1 | `/` ログイン | 共通 | `/`（デモを開始） | `POST /session`・`DELETE /session`（`SessionsController`）、`viewer`（著者判断 3） | M4・M8 |
| 2 | `/settings` 自社の情報 | 共通 | —（新規） | `viewer`（取引用コード `partnerCode` は `admin` だけ） | M8 |
| 3 ※ | `/audit-logs` 監査ログ | 共通 | —（新規） | `viewer.auditLogs`（`admin` だけ） | M19 |
| 4 ※ | `/supplier/dashboard` ダッシュボード | 受注側 | `/dashboard` | `supplier.dashboard`、かんばんは `supplier.salesOrders`、カードの操作は `allocateSalesOrder`・`createShippingInstruction`・`postShipment` | M26・M10・M12・M13 |
| 5 | `/supplier/sales-orders` 受注一覧 | 受注側 | `/orders` | `supplier.salesOrders` | M10（状況の「検収済」は M23、取消審査中の印は M21） |
| 6 ※ | `/supplier/sales-orders/[id]` 受注詳細 | 受注側 | `/orders/[id]` | `supplier.salesOrder`、`allocateSalesOrder`・`createShippingInstruction`・`cancelSalesOrder`・`approveCancellationReview`・`rejectCancellationReview` | M10・M12・M13・M21・M22 |
| 7 | `/supplier/part-mappings` 品番の対応表 | 受注側 | —（新規） | `supplier.partMappings`・`registerPartMapping`、照合待ちの受注は `supplier.salesOrders`、品目の候補は `supplier.items` | M11 |
| 8 | `/supplier/stocks` 在庫と移動履歴 | 受注側 | `/stocks` | `supplier.stocks`・`supplier.stockMovements`・`adjustStock` | M12 |
| 9 | `/supplier/shipment-requests` 出荷依頼 | 受注側 | `/shipping-instructions` | `supplier.shipmentRequests`・`createShippingInstruction`・`cancelShippingInstruction`・`postShipment` | M13（状況の「出荷停止中」は M21） |
| 10 | `/supplier/items` 品目 | 受注側 | `/items` | `supplier.items`・`saveItem`・`setItemPublished` | M9 |
| 11 ※ | `/supplier/items/[id]` 品目の単価の履歴と改定 | 受注側 | —（新規） | `Item.prices(asOf:)`・`scheduleItemPrice`・`correctItemPrice`。品目を ID で引く入口は無い（著者判断 6） | M27 |
| 12 | `/supplier/partnerships` 取引関係 | 受注側 | `/customers` | `supplier.partnerships`・`establishPartnership`・`revokePartnership`・`grantPermission`・`withdrawPermission`（変更は `admin` だけ） | M8 |
| 13 ※ | `/supplier/billing` 請求の締め | 受注側 | —（新規） | `supplier.billingTerms`・`setBillingTerm`・`supplier.billableItems`・`closeBillingPeriod` | M24 |
| 14 ※ | `/supplier/invoices` 請求書一覧 | 受注側 | —（新規） | `supplier.invoices` | M24 |
| 15 ※ | `/supplier/invoices/[id]` 請求書詳細 | 受注側 | —（新規） | `supplier.invoice`・`Invoice.items`・`BillableItem.priceExplanation`・`discardDraftInvoice`・`issueInvoice` | M24・M25・M27 |
| 16 ※ | `/supplier/imports` 取り込みの一覧と開始 | 受注側 | —（新規） | `POST /imports/files`・`startImport`・`supplier.imports` | M29 |
| 17 ※ | `/supplier/imports/[id]` 取り込みの進み具合 | 受注側 | —（新規） | `supplier.import`・`Import.rowErrors`。進行中は数秒ごとに `router.refresh()` で読み直す | M29 |
| 18 | `/buyer/suppliers` 取引先とカタログ | 発注側 | —（新規） | `buyer.suppliers`・`SupplierPartnership.catalog` | M8・M9 |
| 19 | `/buyer/purchase-orders` 発注一覧 | 発注側 | `/orders` | `buyer.purchaseOrders`。入荷を待つ発注は「入荷予定」のタブで見る（著者判断 7） | M10（状況の「入荷予定」は M14、「検収済」は M23、取消は M21・M22） |
| 20 | `/buyer/purchase-orders/new` 発注登録 | 発注側 | `/orders/new` | `buyer.suppliers`（`place_orders` の付与のある相手）・`SupplierPartnership.catalog`（参照に並べる）・`placePurchaseOrder`。品番は自社品番を入力する | M8・M9・M10 |
| 21 ※ | `/buyer/purchase-orders/[id]` 発注詳細（入荷・検収・取消依頼） | 発注側 | `/orders/[id]` | `buyer.purchaseOrder`（`inboundShipments`・`supplierShipments`・`cancellationRequests`）・`inspectInboundShipment`・`requestPurchaseOrderCancellation` | M10・M14・M21・M23 |
| 22 ※ | `/buyer/received-invoices` 受領請求書一覧 | 発注側 | —（新規） | `buyer.receivedInvoices` | M25 |
| 23 ※ | `/buyer/received-invoices/[id]` 受領請求書詳細 | 発注側 | —（新規） | `buyer.receivedInvoice` | M25 |

流用元にあって API に無い操作は、画面から外す。受注側による受注の登録（受注は発注からイベントで作られる）、明細ごとの引当と引当の解除（`allocateSalesOrder` は受注の単位で引き当てる）、品目と得意先の削除、得意先の住所と担当者がこれに当たる。流用元の品目の安全在庫は、在庫の値（`Stock.safetyStock`）として在庫の画面に出す。

受注の状況は、流用元の 6 つから `SalesOrderStatus` の 7 つに替わる。ダッシュボードのかんばんの列は 7 つにし、流用元の「出荷指示済」の列は無くなる。出荷指示の有無はカードの `shipmentRequest.status` が `INSTRUCTED` であることで示し、「出荷実績計上」のボタンを出す。取消審査中と取消依頼中は、状況のバッジに重ねる印で示す（`graphql-schema.md`「状況の enum」）。流用元に無い状況のバッジの色は、著者判断 2 による。

**作るもの 3：データ取得層**

流用元は、サーバーコンポーネントで読み、server action で書き、どちらも Next のサーバーから API を呼ぶ。この形を保ち、呼び先だけを Rails の GraphQL に替える。

- **呼び出し口**：`lib/graphql/request.ts` の 1 か所だけが Rails を呼ぶ。流用元の `lib/api-client.ts`・`api.ts`・`api-types.ts` と、`lib/*-actions.ts` の REST の呼び出しを、これに置き換える。`fetch` は `cache: "no-store"` で呼び、Next のデータのキャッシュ（`"use cache"`・`unstable_cache`・`fetch` の `next.revalidate`）は使わない。キャッシュの鍵にセッションが入らないので、あるテナントへの応答を別のテナントに返すからである。ESLint の `no-restricted-syntax` と `no-restricted-imports` で、これらを書くと落ちるようにする。
- **型の生成**：`@graphql-codegen/cli` が、根の `schema.graphql` と `frontend/graphql/**/*.graphql` から、操作ごとの `TypedDocumentNode` を `lib/graphql/generated.ts` に書き出す。生成物は commit し、CI で生成し直して差分が無いことを確かめる（`npm run codegen:check`）。カスタムのスカラー `BigInt`・`ISO8601Date`・`ISO8601DateTime` は `string` に写す。金額は `BigInt` で足し引きし、`Number` に直さない（`lib/format.ts`）。流用元が API の応答から読んでいた業務日付は、Next のサーバーが Asia/Tokyo の今日として出す。
- **画面の問い合わせ**：`frontend/graphql/<視点>/<操作名>.graphql` に 1 ファイル 1 つで置き、断片（fragment）はそのファイルの中でだけ使う。一覧は絞り込みの引数を使わず、`first: 100` で `pageInfo.hasNextPage` が偽になるまで読み、流用元の並べ替え・絞り込み・タブの純関数にそのまま渡す（著者判断 1）。
- **認証**：ログインの server action が、Rails の `POST /session` に JSON で資格情報を送り、応答の `Set-Cookie` にあるセッションの Cookie（`_factory_ops_session`）を、同じ属性（`HttpOnly`・`SameSite=Lax`・本番は `Secure`・期限）で `cookies().set` に写す。`request.ts` は、ブラウザから届いた Cookie のうちセッションの Cookie だけを Rails へ送る。ログアウトの server action は `DELETE /session` を呼び、Cookie を消す。Rails が応答のたびに延ばす期限の扱いは、著者判断 5 による。
- **`Origin` と CSRF**：ブラウザが見るオリジンはフロントエンドの 1 つだけにし、Rails の CORS は開けない（`guides/config.md`「CSRF を防ぐ前提：CORS を開けない」）。ブラウザからの書き込みは server action を通り、Next が `Origin` と `Host` の一致を確かめる。Next のサーバーは Rails へ `Content-Type: application/json` で送るので、`ApplicationController` の制限をそのまま通る。例外は取り込みのファイル（M29 の `POST /imports/files`）で、`next.config.mjs` の `rewrites` で同じオリジンの下に出し、ブラウザから `multipart/form-data` で送る。Rails は、ブラウザの `Origin` を、許可したオリジン（フロントエンドのオリジン）と比べる。
- **エラー**：`request.ts` が応答を次の表のとおりに分け、画面は分けた結果だけを見る。流用元の `ApiResult` の `code` の一覧は、この分け方に置き換える。ユーザーエラーの `message` は API の文言をそのまま出し、言い換えるのは次にすることを書き足すときだけにする（流用元の `handbook/README.md`「同じ意味を2箇所に実装しない」）。

  | 応答 | 画面の扱い |
  |---|---|
  | HTTP 401 | セッションの Cookie を消し、ログインの画面へ移す |
  | 接続できない・5xx・タイムアウト | 流用元の「API に届かない」表示（`error-notice`・`list-error`）を出す |
  | ID で引く入口（`supplier.salesOrder(id:)` など）の `null`、mutation の `NOT_FOUND` | どちらも流用元の見つからない画面（`not-found-message`）にする。無いのか見えないのかを言い分けない |
  | mutation の `NOT_PERMITTED` | 1 つの文言で出す。失効・付与なし・存在しない相手のどれなのかを、画面で推し量って言い分けない |
  | mutation の `INVALID_INPUT` | `path` の指す入力欄の下に出す。`path` が空ならフォームの上に出す |
  | mutation の `CONFLICT` | 最新の状態を読み直してから、メッセージを出す |
  | トップレベルの `FORBIDDEN` とその他のトップレベルのエラー | 画面の上に、処理できなかったことを出す。`admin` だけの操作のボタンは `viewer.role` が `admin` のときだけ出すので、`FORBIDDEN` は通常は起きない |

- **テナントの切り替え**：ユーザーは 1 つのテナントに属するので、テナントを切り替えるには、ログアウトして別のテナントのユーザーでログインする。画面にテナントを選ぶ欄は置かない。受注側と発注側の切り替えは、同じテナントの中でサイドバーのグループを移ることで行う。

**判断**：Rails をどこから呼ぶか

- **既定の推奨**：Next のサーバー（サーバーコンポーネントと server action）からだけ呼ぶ。ブラウザが Rails を直接呼ぶのは、取り込みのファイルの送信だけにする。流用元の画面部品はこの形で書かれており、そのまま使える。セッションの Cookie はフロントエンドのオリジンの Cookie になり、CORS を開けずに済む。
- **裏返る条件**：ブラウザで頻繁に読み直す画面や、楽観的な更新が要る画面が増える → その画面だけ、Next の route handler を挟んでブラウザから呼ぶ。Rails へは route handler が同じ呼び出し口で送る。
- **撤退コスト**：中。呼び出し口は `request.ts` の 1 か所だが、画面ごとにクライアントコンポーネントへ書き換えることになる。

**判断**：GraphQL のクライアント

- **既定の推奨**：codegen の `TypedDocumentNode` と、`fetch` の薄い包み（`request.ts`）だけにする。Apollo Client と urql は入れない。読みはサーバーで毎回取り直すので、正規化したキャッシュの出番が無い。
- **裏返る条件**：上の判断が裏返り、ブラウザで読む画面が増える → urql を入れ、ブラウザ側の読みだけをそれで書く。
- **撤退コスト**：小。生成した型はどのクライアントでも使える。

**判断**：画面の問い合わせの正本をどこに置くか

- **既定の推奨**：`frontend/graphql/` を正本にする。M17 の `spec/fixtures/graphql/screens/` を消し、クエリ数の予算（M17）・複雑度のテスト（M26）・操作名の登録の一致のテスト（M30）が `frontend/graphql/` を読むように替える。画面が実際に送る問い合わせと、検査する問い合わせが 1 つになる。
- **裏返る条件**：`frontend/` を別のリポジトリに置く → `spec/fixtures/graphql/screens/` を残し、フロントエンドの CI で両者の一致を確かめる。
- **撤退コスト**：小。3 つのテストの読み先を 1 行ずつ替えるだけである。

**作るもの 4：テストとゲート**

流用元の E2E は、Go の API に当てる live と、REST のスタブに当てる stub の 2 系統である。本デモは、Rails に当てる 1 系統にする。stub が作っていた「API に届かない」状態は、届かない URL を向いた Next のサーバーをもう 1 つ立てて作る。

- **E2E の世界**：Playwright の `webServer` が、`bin/rails server`（`RAILS_ENV=test`、DB は `factory_ops_e2e`）・`bin/jobs`（イベントを流す）・`next start` を起こす。起こす前に、`bin/rails e2e:prepare[ワーカー数]`（`lib/tasks/e2e.rake`、test の環境でだけ動く）が DB を作り直し、Playwright のワーカーごとに、M32 のシードと同じ形の世界（受注側 1 社・発注側 2 社・各社のユーザー）を公開 API とイベントで 1 組ずつ作る。テストは、自分のワーカー番号の世界のユーザーでログインし、他の世界に書かない。
- **画面の通し試験**：E2E に次の 2 本を置く。1 本目は、重要シナリオ S2（M26）を画面で通す。失効の後、発注側の取引先とカタログと出荷が空になり、発注登録が `NOT_PERMITTED` の文言になる。2 本目は、発注側の 2 社のユーザーで続けてログインし、前のテナントの伝票番号が画面に出ないことを確かめる。
- **流用元の規則**：流用元の `handbook/README.md` の E2E と見た目の規則を、次のとおり持ち込む。

  | 流用元の規則 | 本デモでの置き方 |
  |---|---|
  | 同じ種類の要素の寸法・そろえ・はみ出しを、最初のタスクで全画面について測る | 流用元の `e2e/support/tokens.ts`・`table-align.ts`・`contrast.ts` と、カードの高さ・はみ出し（`scrollWidth <= clientWidth`）の検査を写し、M33 の最初の作業で置く。測る画面の一覧は `app/` のルートのファイルから作り、手で並べない。足した画面が測られないまま通らないようにするためである |
  | 中身の違うデータを作ってから測る | E2E の世界に、最も長い品目名と取引先名、ボタンのある行と無い行、各状況の enum の全値の行を入れる。シードの短くそろった中身だけで測らない |
  | 寸法・色・フォーカスは、アニメーションと色の遷移が終わってから測る。キーは 1 つ押すごとにフォーカスの移りを待つ | 流用元の `e2e/support/style.ts`・`router.ts` の待ち方をそのまま使う |
  | 数える前に画面の変化を待ち、遷移の後は着いたことを先に確かめる | 同上。イベントで進む表示（発注 → 受注確定）はワーカーの処理を待つので、`expect.poll` と再読み込みで待ち、固定の時間は待たない |
  | 1 回だけ落ちたテストを、再実行で緑にして流さない | CPU の遅延（CDP の `Emulation.setCPUThrottlingRate`）で再現率を測り、待ち方の誤りか製品の競合かを分ける。Playwright の `retries` は 0 にする |
  | 集計の数字と、そこから飛ぶ一覧は、同じ条件で絞る | ダッシュボードの状況ごとの件数と、受注一覧のタブの件数が一致することを E2E で確かめる |
  | テストは、壊したときに落ちて初めて意味を持つ | 本リポジトリの「守りの検査は、外すとテストが落ちることを確かめる」（`handoff.md`「1 つのマイルストーンの回し方」）と同じに扱う |
  | 見せる前に、同じ種類の要素どうしをスクリーンショットで見比べる | 検収表（画面 × ライト・ダーク × 1280・1024・390px）のスクリーンショットを撮り、担当者が見比べてから作者に見せる。作者が受け入れるまで M33 を終えない |

  流用元の開発の進め方（台帳・交差レビュー・RED と GREEN の push の規約）と、配信先のエッジに掛かる上限の検査は持ち込まない。本書の「1 つのマイルストーンの進め方」と、`handoff.md` のレビューの回し方に従う。
- **CI**：`.github/workflows/ci.yml` にジョブを 2 つ足す。`frontend` は、`npm ci`・`npm run codegen:check`・`npm run lint`（コメントの検査を含む）・`npm run typecheck`・`npm run test:unit` を流す。`e2e` は、既存の test のジョブと同じ PostgreSQL 18 のサービスとロールの準備をし、Ruby と Node を入れ、`npx playwright install --with-deps chromium` の後に `npm run test:e2e` を流す。

**完了条件**

```sh
cd frontend && npm run codegen:check && npm run lint && npm run typecheck && npm run test:unit
cd frontend && npm run test:e2e
bundle exec rspec spec/graphql/query_budget_spec.rb   # 画面の問い合わせを frontend/graphql から読む
```

次を、手で確かめる。`schema.graphql` から画面が使うフィールドを 1 つ消すと、`npm run codegen:check` か `npm run typecheck` が落ちる。`request.ts` に `"use cache"` を足すと、`npm run lint` が落ちる。作者が検収表のスクリーンショットを見て受け入れる。

**著者判断（着手の時に作者に確かめる）**：次の点は既定を置いて計画した。担当者は、着手の前に作者に確かめ、答えが既定と違えば、本節を先に直してから作る。

1. **一覧の読み方**：一覧は全ページを読み切ってから、流用元の純関数で並べ替え・絞り込み・タブの件数を出す。500 件で読むのをやめ、やめたことを画面に出す。GraphQL の一覧は `totalCount` も並べ替えの引数も持たない（`graphql-schema.md`「ページングと N+1」）ので、1 ページだけを並べ替えると、並べ替えが嘘になるからである。上限を超える一覧が日常になるなら、コネクションに並べ替えの引数を足し、サーバーで並べる。
2. **状況のバッジの色**：流用元に無い状況（品番照合待ち・検収済・発注の各状況・出荷依頼・取り込み・請求書）は、意味の近い流用元の状況の色を使い回し、色のトークンを足さない。作者が色での区別を求めるなら、トークンを足し、流用元の図形のコントラストの検査に載せる。
3. **ログインの画面**：メールアドレスとパスワードの入力欄に、M32 のシードのアカウント（メールアドレスと、共通のパスワード）の一覧を並べ、押すと入力欄に入る。一覧は `db/seeds/demo_accounts.json` の 1 か所に置き、シードとフロントエンドの両方が読む。
4. **サイドバーと最初の画面**：テナントは発注側と受注側のどちらにもなりうるので、サイドバーには両方のグループを常に出す。ログインの直後は、`supplier.partnerships` が空でなければ受注側のダッシュボードへ、空なら発注側の発注一覧へ移す。
5. **セッションの期限**：Rails は、応答のたびにセッションの Cookie を書き直して期限を延ばす。サーバーコンポーネントは Cookie を書けないので、延びた Cookie は server action の応答でだけブラウザに写す。読むだけの利用では、期限はログインか最後の書き込みから 12 時間になる。
6. **入口に足すフィールド**：品目を ID で引く `supplier.item(id:)` と、サイドバーに自社の名前を出す `viewer.tenant` が無い。どちらも足すだけの変更なので、M33 で足し、`graphql-schema.md` と行列テストの期待値に行を足す。
7. **入荷の一覧**：発注をまたいだ入荷の一覧の入口（`buyer.inboundShipments`）は足さず、発注一覧の「入荷予定」のタブで代える。検収は発注詳細で行う。
8. **公開の配置**：手元（`bin/rails server` と `next start`）で見せるところまでにする。公開する配置と、訪問者ごとのデータの分離（流用元のデモの開始に当たるもの）は作らない。

**範囲外**：公開の配置と訪問者ごとのデータの分離（著者判断 8）、流用元のデモの開始・サンプル表示・混雑の通知、API に無い操作（「作るもの 2」の末尾）、通知メールの設定画面、流用元のこれからの変更の取り込み（置き場所の判断の裏返る条件に当たるまで）。

**実装する文書の節**：`graphql-schema.md`「1 回のリクエストがたどる道」1・「視点ごとに型を分ける」・「状況の enum」・「エラー」・「ページングと N+1」、`guides/config.md`「CSRF を防ぐ前提：CORS を開けない」、`handoff.md`「目的」、流用元の `docs/specs/cycle-03-visual-refresh-spec.md` §2（トークン）・§3（外枠と共通部品）・§9（ダッシュボード）・§11（検収表）と `handbook/README.md`

**文書に残すこと**：画面の問い合わせの置き場を、本書の M17 と `graphql-schema.md`「ページングと N+1」で `frontend/graphql/` に書き直す。`guides/comments.md` の対象に `frontend/` を足す。著者判断 6 で足したフィールドを `graphql-schema.md`「視点ごとに型を分ける」に書く。`README.md` の「構成」に、フロントエンドの起動の手順を書く。
