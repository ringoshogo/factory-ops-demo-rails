# 実装計画

設計文書（`architecture/`・`adr/`）を、動くアプリに落とす順番を定める。実装を担当するエージェントは、マイルストーンを M1 から番号の順に 1 つずつ実装する。1 つのマイルストーンは 1 回の作業で終わる大きさ（数百行）にしてある。

## 1 つのマイルストーンの進め方

担当者は、マイルストーンに着手するたびに次の順で進める。計画レビュー・実装レビュー・残件の台帳を含む回し方の全体は、`guides/dev-cycle.md` にある。

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
bin/check-open-items --due M<番号>            # 引当先がこのマイルストーンの残件が、open と blocked-user のまま残っていない
```

`bin/check-structure` は、開発の DB にマイグレーションを流した結果と、`structure.sql` を読み込み直して書き出した結果が、どちらも `structure.sql` と一致することを確かめる。空の DB への `db:migrate` は `structure.sql` を読み込むだけでマイグレーションを流さないので、`structure.sql` を退避してから流す。文字列の列の CHECK 制約は `status::text IN (...)` と書く。`status IN (...)` と書くと、マイグレーションの結果と読み込み直した結果で式の表記が変わり、この検査が落ちる。

packwerk の違反は `package_todo.yml` に逃がさず、その場で直す（`adr/002`）。

## 環境

次の値は決まっている。担当者は変えない。

| 項目 | 値 |
|---|---|
| Ruby | 3.4.11（rbenv）。版は `.ruby-version` に書き、`Dockerfile` の `RUBY_VERSION` を同じ版にする。この版にする理由は `Dockerfile` の `RUBY_VERSION` の直前のコメントにある |
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

M34・M35 は、サイクル 01 の改善の探索（`plans/cycle-01/improvement.md`）で採用した変更である。M21 より前に実装する（`guides/dev-cycle.md`「全体の流れ」）。M21 以降の番号を振り直すと、台帳・証跡・文書の参照が崩れるので、番号は末尾に足し、節は実装の順に M20 の後へ置く。

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
| M34 | 依存の更新と使っていない部品の削除 | 読み込む Rails の部品が `guides/config.md` の記述と一致し、保守の続く Ruby で動く |
| M35 | 分岐の網羅率の警告 | PR が足した行の分岐のうち、どの example も通らないものが CI の警告に出る |
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
| M17 | M14・M16 | クエリ数の予算の対象の問い合わせが M14 までの入口を使い、Bullet の対象外を M16 の競合テストの置き場で決める |
| M18 | M4・M7 | 文脈を `GraphqlController` と `ApplicationJob`・`Contracts::EventJob` で設定する |
| M19 | M16・M18 | 監査ログの相関 ID を、M18 の文脈から取る。競合テストの後始末を、M16 の `concurrency` の置き場のテストに対して決める |
| M20 | M5 | スキーマを書き出す |
| M34 | M18・M20 | 依存の更新で、M18 のログの衛生の spec が止めた経路を確かめる。M20 の 2 つ目の PR（CI の互換の検査）の後に CI の設定を変える |
| M35 | M34 | 分岐の網羅率を、上げた後の Ruby で測る |
| M21〜M26 | M15〜M20・M34・M35 | 新しい mutation に監査の宣言を、イベントに付帯情報を、テストに層を、型の変更に `schema.graphql` の書き直しを伴わせる。上げた Ruby で書き、足した分岐の未通過を警告で見る |
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

**目的**：`context-map.md`「疎結合を守る規則」の依存の向きの表を packwerk の依存チェックで、公開 API の限定をプライバシーチェックで、CI が強制する。

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

**文書に残すこと**：`context-map.md`「疎結合を守る規則」の依存の向きの表に `platform` を足し、`contracts` の依存先を「`platform` だけ」に直す（コンテキストに属さないパッケージの表にも足す）。`adr/002` の未確認の事項を、確かめた結果で置き換える。packs-rails を外した場合は、その手順を `adr/002` に書く。

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

**実装する文書の節**：`context-map.md`「発注の連結と品番の照合」1〜4、`data-model.md`「購買（`purchasing`）」「受注（`sales`）」「イベントの受け口と冪等キー」の該当行

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

- カスタム Cop `FactoryOps/NoHistoryComment`（`lib/rubocop/cop/factory_ops/no_history_comment.rb`）：`processed_source.comments` を走査し、`guides/comments.md`「機械で止めるもの」の語を含むコメントを落とす。マイルストーンの番号は `(?<![A-Za-z0-9_])M\d+(?![A-Za-z0-9_])` で判定する。`\b` は和文の文字を語の一部とみなすので、「停止中はM15で足す」のように和文に挟まった番号を見逃す。`.rubocop.yml` で全 Ruby ファイルに有効にする。Cop が守るのは Ruby のコメントだけで、YAML・SQL・ERB などのコメントは `guides/comments.md`「機械で止めるもの」の `git grep` とレビューで確かめる。
- `spec/rubocop/cop/factory_ops/no_history_comment_spec.rb`：`guides/comments.md` の良い例が通り、悪い例が落ちることを確かめる。
- 既存のコメントの掃除：Cop が落とす箇所をすべて書き直す。spec の冒頭のコメントは、`implementation-plan.md` のマイルストーンではなく、その spec が守る規則と設計文書の節を指す形にする。コードに残っている `M15`・`M17` などの番号は、本書の番号を付け直す前のもので、いまの M15・M17 とは別物である。番号で指していた先は、設計文書の節に置き換える。

**判断**：コメントの規約を Cop で止めるか、レビューに任せるか

- **既定の推奨**：語の一覧で止める Cop を置く。規約を文書にだけ書くと、人が入れ替わるたびに消える（`decisions.md` 7 章）。語で判定できない規則（コードの言い直しをしない、など）はレビューに残す。
- **裏返る条件**：誤検知で言い換えが日常になり、Cop を無効にするコメントが増える → 語の一覧を絞り、外した語をレビューの観点に移す。
- **撤退コスト**：小さい。Cop を外すだけで済む。

**完了条件**

合否は次の 2 つで決める。どちらも、違反が残れば終了コードで落ちる。

```sh
bin/rubocop                      # Ruby のコメントに語が残っていない
bundle exec rspec spec/rubocop   # Cop が悪い例を落とし、良い例を通す
```

担当者は、Ruby 以外のファイルのコメントを `guides/comments.md`「機械で止めるもの」の `git grep` で確かめ、当たった行を直すか報告する。この検索は文字列の中の語も拾い、当たっても終了コードで落ちないので、合否には使わない。検索は `-P` で流し、番号の前後は ASCII の英数字で区切る。macOS の git は `-E` の `\b` を解さないことがあり、番号が残っていても何も返さない。`\b` は和文の文字も語の一部とみなすので、和文に挟まった番号を見逃す。

**実装する文書の節**：`guides/comments.md`、`decisions.md` 7 章

**文書に残すこと**：Cop の語の一覧を変えたら、`guides/comments.md`「機械で止めるもの」を同じ変更で直す。

## M16 テストの層と重要シナリオ

**目的**：テストの大半を、速く、落ちた場所から原因が分かる単体テスト（公開 API・モデル・policy）に置く。壊れると事故になる業務の流れだけを、専用のシナリオテストで端から端まで確かめる。CI は、層ごとの件数・割合・時間を毎回報告する。

**作るもの**

層の定義・層への配分の規則・競合テストの置き場・重要シナリオの表は `guides/testing.md` にある。本節は、このマイルストーンで作るものだけを挙げる。

- テストの層の定義（`config/test_layers.yml`）と、`guides/testing.md`「テストの層」の表
- `bin/test-layers`：rspec の JSON の出力を読み、層ごとの件数・割合・時間を表にして、標準出力と `$GITHUB_STEP_SUMMARY` に書く。example の層は JSON の `id` のファイルの部分で決め、未分類のファイルがあれば失敗し、割合が目安を外れたら警告の注釈を出す（`guides/testing.md`「テストの層」）
- 競合テストの置き場：既存の競合テスト（在庫の行ロック・発注と失効・受注の引当・品番の対応表の登録）を `concurrency` の置き場へ移す。`spec/rails_helper.rb` は、置き場から `:concurrency` と `:scenario` のメタデータを付け、`spec/spec_helper.rb` は `config.fail_if_no_examples = true` にする（`guides/testing.md`「競合テスト」「重要シナリオ」）
- CI：`.github/workflows/ci.yml` と `config/ci.rb` の rspec のステップを、`bundle exec rspec --format progress --format json --out tmp/rspec.json` にし、続けて `bin/test-layers tmp/rspec.json` を流す
- 重要シナリオの S1・S3 と、S4 のうち計上・引当・出荷指示の取消の競合（`guides/testing.md`「重要シナリオ」）。S1 は、ID を取る入口をスキーマから集め、表に無い入口があれば落ちる（`guides/testing.md`「S1 の入口の列挙」）

**判断**：層の割合を CI の失敗にするか

- **既定の推奨**：報告と警告にとどめ、未分類のファイルだけを失敗にする。割合は機能の種類で揺れる（GraphQL の入口だけを足すマイルストーンでは結合が増える）。未分類を止めれば、数え方は崩れない。
- **裏返る条件**：シナリオの割合が 50% を超え、見直しても下げられない → 層の分け方と置き場を見直す。割合を失敗の条件にはしない。割合に合わせてテストを書き足すと、テストが業務の分岐ではなく数に引かれるからである（OI-24）。
- **撤退コスト**：小さい。`bin/test-layers` の終了コードを変えるだけで済む。

> 手で書いた example の数（行列テストのように生成する分を除く）は、M14 の時点で、単体（`packs/*/spec`）が約 90、結合（`spec/requests`・`spec/contracts`）が約 90 だった。

**完了条件**

```sh
bundle exec rspec --format progress --format json --out tmp/rspec.json
bin/test-layers tmp/rspec.json   # 層ごとの表が出て、未分類のファイルが無い
bundle exec rspec spec/scenarios/tenant_boundary_spec.rb spec/scenarios/order_linking_spec.rb   # S1・S3 のファイルがあり、example が集まる
bundle exec rspec --tag scenario      # 0 件なら失敗する（fail_if_no_examples）
bundle exec rspec --tag concurrency   # 同上
```

上の自動の条件に加えて、担当者は、S1 が防壁を検査していることを、次の 2 つの壊し方で手で確かめ、落ちた example の名前を PR に書く。手の確認は自動の条件の代わりにならない。確かめた後は戻す。落ちなければ S1 がその防壁を検査していないので、example を足してから完了にする。

1. アプリの防壁：`Purchasing::Ordering.place` の `Partnerships::Access` の確かめを外す → 取引関係の無い相手のテナント ID で `placePurchaseOrder` を呼ぶ example が落ちる。
2. 2 枚の防壁：`Sales::SalesOrderPolicy` の scope の自社テナントの条件を外し、所有ロールで `ALTER TABLE sales_orders DISABLE ROW LEVEL SECURITY` を流す → 受注側の受注 ID を、発注側のユーザーが `supplier.salesOrder(id:)` と `allocateSalesOrder` に渡す example が落ちる。scope と RLS はそれぞれ単独で他社の受注を除くので、片方だけを外しても落ちない。

**実装する文書の節**：`decisions.md` 7 章、`adr/005` 決定 6（テストでのジョブの扱い）

**文書に残すこと**：層の定義・競合テストの置き場・request spec に残す規則・重要シナリオの表は `guides/testing.md` にある。置き場を変えたら、`config/test_layers.yml` と同じ変更で直す。

## M17 N+1 の検出

**目的**：公開 API の中で関連を 1 件ずつ読む N+1 を、Bullet でテストの失敗にする。GraphQL のフィールドが親ごとに公開 API を呼ぶ N+1 は Bullet に見えないので、問い合わせごとのクエリ数の予算で落とす。

**作るもの**

- Bullet（`~> 8.2`）を test と development のグループに入れる。`config/environments/test.rb` は `Bullet.enable`・`Bullet.raise`・`Bullet.n_plus_one_query_enable` を真に、`Bullet.unused_eager_loading_enable`・`Bullet.counter_cache_enable` を偽にする。development は `Bullet.bullet_logger` で記録だけにする。どちらも `config.after_initialize` のブロックの中で設定する。`Bullet.enable = true` は、その場で `ActiveRecord::Base` を拡張するので、設定のブロックに直接書くと、Active Record が初期化の途中で読み込まれる。
  - 使わない先読みの検出を外す理由：`Bullet.raise` は検出の種類を問わず例外にする。公開 API は、値の組み立てに要る関連を GraphQL の選択によらずまとめて先読みするので、使わない先読みの報告は直す対象にならない。
  - カウンタキャッシュの検出を外す理由：状況と件数は時刻列と公開 API で導出し（`data-model.md`「状態は保存せず、時刻列から導出する」）、カウンタキャッシュの列を持たない。
- `spec/support/bullet.rb`：各 example を `around` で `Bullet.profile { example.run }` に包む。`Bullet.profile` は、`start_request` で検出を始め、example の後に検出があれば `perform_out_of_channel_notifications` で通知し（`Bullet.raise` なので例外になる）、`ensure` で `end_request` を呼ぶ。`start_request` と `end_request` だけで包むと、検出しても通知されず、`end_request` が検出の状態を消すので、example は通る。`bullet: false` か `:concurrency` のメタデータを持つ example は包まない。
  - HTTP の要求を流す example（`type: :request`）：`spec/rails_helper.rb` が `type: :request` から `bullet: false` を付ける。Bullet は、HTTP の要求を自分のミドルウェア（`Bullet::Rack`）で同じ手順で包む。外でも包むと、ミドルウェアの `start_request` と `end_request` が外の検出の状態を上書きして消すので、二重に管理しない。要求は `spec/requests` の外（シナリオ・行列テスト）でも流すので、置き場では決めない。要求の外でイベントを受け手まで流す補助（`deliver_enqueued_events`・`deliver_oldest_event`）は、検出の外で呼ばれたら自分で `Bullet.profile` に包む。
  - `:concurrency` のメタデータを持つ example（M16）：別のスレッドで操作する。Bullet は検出の状態をスレッドごとに持つので、別のスレッドの読み込みは見えない。
  - 包みが出す例外は、example が終わった後の `around` の中で起きる。example の中の `expect { }.to raise_error` では捕まえられないので、例外を確かめる example は `bullet: false` を付け、自分で `Bullet.profile` を呼ぶ。
- 一覧のテストの規則：Bullet は、1 回の読み込みで 1 件しか返らなかったレコードを N+1 の候補にしない。担当者は、一覧を返す公開 API のテストで、親を 2 件以上作り、それぞれの関連を読む値を確かめる。
- `spec/platform/bullet_spec.rb`：検出が例外まで届くことを、意図的な N+1 で確かめる。親を 2 件作り、先読みせずに関連を 1 件ずつ読む処理を、次の 3 つの経路で動かし、どれも `Bullet::Notification::UnoptimizedQueryError` になることを確かめる。ファイル全体に `bullet: false` を付け、自動の包みから外す。
  1. 公開 API を直接呼ぶ：`expect { Bullet.profile { 呼び出し } }.to raise_error(...)` で、`spec/support/bullet.rb` と同じ包み方を確かめる
  2. Dataloader のソースの中：同じく `Bullet.profile` の中で、`FactoryOpsSchema.execute` を呼び、その処理をソースから呼ぶフィールドを解決する
  3. `/graphql` への要求：`expect { post "/graphql", ... }.to raise_error(...)`。`Bullet::Rack` は `ActionDispatch::ShowExceptions` の内側にあり、テストの `show_exceptions = :rescuable` は対応表に無い例外を応答に変えずに投げ直すので、`post` 自身が例外を出す
- 許可リスト：`spec/support/bullet_safelist.rb` に `{ type:, class_name:, association:, reason: }` の配列で書き、`Bullet.add_safelist` に渡す。`reason` の無い行は、読み込みの時点で例外にする。許可してよいのは、件数が 1 に決まっている誤検知（1 件のレコードを引いてから関連をたどる、など）だけである。本当の N+1 を許可リストで黙らせない。
- 画面の問い合わせの一覧（`spec/fixtures/graphql/screens/*.graphql`）：画面が送る問い合わせを、操作名を付けて 1 ファイル 1 つで置く。M17 では、M33 の画面の一覧のうち M14 までの入口で動く画面について、次の表の問い合わせを作る。後のマイルストーンは、入口を足すたびに、それを使う画面の問い合わせをここへ足す。M26 の複雑度のテストと M30 の操作名の登録も、この一覧を使う。

  | 操作名 | 画面（M33） | 操作者 | 一覧の親 | 選ぶ入れ子 |
  |---|---|---|---|---|
  | `SupplierSalesOrders` | 5・7 | 受注側の `member` | `supplier.salesOrders` | `customer`・`lines`・`shipmentRequest` |
  | `SupplierShipmentRequests` | 9 | 受注側の `member` | `supplier.shipmentRequests` | `salesOrder`・`customer`・`lines`・`instruction` |
  | `SupplierItems` | 7・10 | 受注側の `member` | `supplier.items` | `stock` |
  | `SupplierStocks` | 8 | 受注側の `member` | `supplier.stocks` | `item` |
  | `SupplierStockMovements` | 8 | 受注側の `member` | `supplier.stockMovements` | `item` |
  | `SupplierPartMappings` | 7 | 受注側の `member` | `supplier.partMappings` | `customer`・`item` |
  | `SupplierPartnerships` | 12 | 受注側の `admin` | `supplier.partnerships` | `buyer`・`permissions` |
  | `BuyerSuppliers` | 18・20 | 発注側の `member` | `buyer.suppliers` | `supplier`・`permissions` |
  | `BuyerSupplierCatalog` | 18・20 | 発注側の `member`（相手から `view_catalog` の付与あり） | `buyer.supplier(supplierTenantId:)` で選んだ取引先の `SupplierPartnership.catalog` | なし |
  | `BuyerPurchaseOrders` | 19 | 発注側の `member`（相手から `view_shipments` の付与あり） | `buyer.purchaseOrders` | `supplier`・`lines`・`inboundShipments`・`supplierShipments` |

  一覧の中にコネクションを入れ子にした問い合わせは、親ごとにページングの問い合わせが出るので、画面の問い合わせに置かない。カタログは、取引先を 1 つ選ぶ入口（`buyer.supplier(supplierTenantId:)`）で選んでから引く（`BuyerSupplierCatalog`）。
- `spec/graphql/query_budget_spec.rb`：画面の問い合わせの一覧の問い合わせごとに、一覧の親が 1 件のときと 20 件のときの SQL の件数が同じであることを確かめる。spec は、問い合わせごとに次を決めて流す。
  - **操作者と変数**：上の表の操作者でログインした状態の `context` を作る。一覧の親がコネクションの問い合わせは、変数の `first` に 20 を明示し、1 ページの件数の既定に頼らない。リストで返す一覧（`supplier.partnerships`・`buyer.suppliers`）は `first` を持たない。
  - **親と子の作り方**：親を 1 件と 20 件作り、入れ子の件数を問い合わせごとに表で持つ。リストの入れ子は、業務の制約が許す範囲で各親に 2 件作る。`BuyerPurchaseOrders` の `inboundShipments`・`supplierShipments` は、分納しない（`data-model.md` の `shipments.shipment_request_id` 一意）ので発注ごとに 1 件にする。単数の入れ子は各親に 1 件作る。
  - **関連先を親ごとに変える**：関連先の ID で引く入れ子（`customer`・`supplier`・`buyer`・`item`・`salesOrder` など）は、親ごとに別の関連先を作る。20 件の親が同じ関連先を指すと、ソースの中ではキーが 1 つにまとまり、ソースを外しても同じ SQL が `cached: true` になって数えられないので、N+1 が件数に出ない。親の ID で引く入れ子（`lines` など）は、もともと親ごとに違う。
  - **応答の確かめ**：件数を比べる前に、応答に `errors` が無いこと、一覧の件数が 1 件と 20 件であること、表の入れ子の件数が各親で作った件数と一致することを確かめる。認可の失敗や空の一覧で件数がそろう場合を、通さないためである。
  - **数える区間と除くもの**：数えるのは `FactoryOpsSchema.execute` の呼び出しの間の `sql.active_record` だけで、データの準備の SQL を含めない。名前が `SCHEMA`・`TRANSACTION`・`Tenancy`（`Tenancy.with_tenant` が流す `set_config`）のものと、`cached: true` のものを除く。
  - **負例**：入れ子ごとに、その入れ子を引く `Sources::PublicApiSource`（公開 API とメソッドの組）の `fetch` を、キーを 1 つずつ渡して公開 API を呼ぶ形に包み、1 件と 20 件で件数が違うことを確かめる。違わなければ、準備のデータが N+1 を件数に出せていないので、関連先の作り方を直す。

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
bundle exec rspec spec/platform/bullet_spec.rb spec/graphql/query_budget_spec.rb
```

Dataloader を外したときにクエリ数の予算が落ちることは、`query_budget_spec.rb` の負例が毎回確かめる。

**実装する文書の節**：`graphql-schema.md`「ページングと N+1」、`decisions.md` 6 章（N+1 対策）

**文書に残すこと**：一覧のテストで親を 2 件以上作る規則と、一覧の中にコネクションを入れ子にしない規則を、`graphql-schema.md`「ページングと N+1」に書く。

## M18 構造化ログと相関 ID

**目的**：障害の原因を、ログだけで辿れる。1 行のログが、どのリクエスト・テナント・ユーザー・GraphQL の操作・ジョブ・イベントのものかを持つ。発注側の発注から受注側の受注確定までのように、テナントをまたぐ一連の処理を、1 つの相関 ID で引ける。個人情報と秘密は書かない。

**作るもの**

- ログの出口：Rails 8.1 の `Rails.event`（`ActiveSupport::EventReporter`）を、ログの出口にする。Rails 8.1 は、コントローラ・ジョブ・Active Record の計装を、構造化イベント（`action_controller.request_completed`・`active_job.started`・`active_job.completed` など）として `Rails.event` に出す。イベントをログに書く購読者は付属しないので、`Platform::JsonLogSubscriber`（`packs/platform`）を `Rails.event.subscribe` で登録する。購読者は 1 件のイベントを 1 行の JSON（`name`・`payload`・`tags`・`context`・`timestamp`）にして、本番では標準出力に、開発とテストでは `log/events.log` に書く。`payload` には、下の「イベントごとに書く項目」の表にある項目だけを入れる。
- イベントごとに書く項目：Rails の構造化イベントは、要求の引数・ジョブの引数・例外のメッセージを載せる。`filter_parameters` は名前で値を隠すだけで、GraphQL の `query` と `variables` の中身や自由記述を覆わない。購読者は、イベントの名前ごとに書く項目を次の表で決め、表に無い項目を落とす。

  | イベント | 書く項目 | 置き換え・落とすもの |
  |---|---|---|
  | `action_controller.request_started` | `controller`・`action`・`format` | `params` は書かない。`GraphqlController` の要求は、`operationName`、`query` の SHA-256 の要約、`variables` のキーの一覧に置き換える |
  | `action_controller.request_completed` | `controller`・`action`・`status`・`duration_ms` などの数値 | — |
  | `action_controller.rescue_from_handled` と、`active_job.*` の例外を伴うもの | 例外のクラス名 | `exception_message` は書かない。メッセージは DB のエラーの詳細などに入力の値を含む |
  | `active_job.*` | `job_class`・`job_id`・`queue`・時間 | `arguments` は書かない。`ApplicationJob.log_arguments = false` にし、購読者も落とす |
  | アプリのイベント（下の「アプリが出すイベント」） | 定義した項目 | — |
  | 上の表に無いイベント | 無し（`name`・`context`・`timestamp` だけを書く） | `payload` 全体 |

- フレームワークの文字列のログ：JSON の書式は、文字列の中の秘密やクエリの本文を消さない。そこで、値を文字列のまま `Rails.logger` に書くフレームワークの経路を、書式に頼らず止める。Rails 8.1.4 で止める経路は次の 3 つである。担当者は着手時に、Solid Queue を含めて、ほかに `Rails.logger` へ直接書く経路が無いかをソースで確かめる。
  - **ログの購読**：`ActionController::LogSubscriber`・`ActionDispatch::LogSubscriber`・`ActiveJob::LogSubscriber` を外す。構造化イベントと同じ内容を、params・ジョブの引数・例外のメッセージ込みの文字列で書く。
  - **要求の開始の行**：`Rails::Rack::Logger` は、購読ではなく自分で `Rails.logger.info` を呼び、`request.filtered_path` を書く。`filtered_path` は `filter_parameters` の名前で隠すだけなので、URL の `query`・`variables` の値が残る。本番とテストでは、このミドルウェアを外す。外して失う `request.action_dispatch` の計装は、Rails 8.1.4 の中に購読者が無く、M30 も使わない。
  - **例外の行**：`ActionDispatch::DebugExceptions` は、捕まえた例外のメッセージとバックトレースを `fatal` で書く。本番ではこれが唯一の役目なので、ミドルウェアから外す。例外は `ActionDispatch::Executor` がエラー通知に送り、ログには `action_controller.request_completed` の状態コードが残る。

  残る `Rails.logger` の行は、JSON の書式（`Platform::JsonLogFormatter`）で書き、同じ文脈を JSON の `context` に入れる。
  - ロガーの構成：`Platform::Logging.build(io)` が、`Platform::JsonLogFormatter` を付けた `ActiveSupport::Logger` を作る。`ActiveSupport::TaggedLogging` で包まない。TaggedLogging は、タグを文字列としてメッセージに混ぜてから書式に渡すので、要求 ID などはタグにせず、文脈から `context` の項目に入れる（`guides/config.md`「ログの出口：Rails.event と Rails.logger」）。Rails は `config.logger` を TaggedLogging で包まず、ジョブのログは、ロガーが `tagged` を持たなければタグを付けない。リクエスト ID などは、タグではなく文脈から JSON に入る。
  - 構成の入口：要求の文脈を設定するミドルウェアの登録と、ログの書式の設定を分ける。文脈はどの環境でも要るが、JSON の書式は本番とテストだけに掛けるからである。
    - **文脈のミドルウェア**：`config/application.rb` が、全環境で `config.middleware.insert_before Rails::Rack::Logger, Platform::RequestContext` を呼ぶ。開発では `Rails::Rack::Logger` が直後に残り、要求の開始の行を、文脈を設定した後に Rails の文字列のまま書く。
    - **ログの書式**：`Platform::Logging.configure!(config, io)` が、`config.logger` の設定・`config.log_tags` の消去・`Rails::Rack::Logger` と `ActionDispatch::DebugExceptions` の削除・`config.after_initialize` での購読の解除をまとめて行う。`config/environments/production.rb`（`STDOUT`）と `config/environments/test.rb`（`log/test.log`）がこれを呼ぶ。Rails は `config.middleware` の挿入をすべて当ててから削除を当てるので、`Rails::Rack::Logger` を消しても、`Platform::RequestContext` はその位置に残る。ミドルウェアの構成は起動の時点で決まり、spec の中から変えられないので、衛生の spec が本番と同じ構成を通るには、テストの環境も同じ入口を通す必要がある。開発の環境は、読みやすさのため Rails の文字列のログのままにする。
    - 設定の時点では自動読み込みが効かないので、`Platform::Logging`・書式・`Platform::RequestContext` は `packs/platform/lib/platform/` に置き、`config/application.rb` と環境のファイルから `require_relative` で読む。
- 文脈：`Rails.event.set_context` で次の項目を設定する。同じ場所で、エラー通知の文脈（`Rails.error.set_context`）にも `request_id`・`tenant_id`・`user_id`・`correlation_id` を設定する。エラー通知にテナント ID を付けるためである（`decisions.md` 2 章「テナント文脈のログへの伝播」）。

  | 項目 | 設定する場所 |
  |---|---|
  | `request_id`（要求） | `Platform::RequestContext`（`env["action_dispatch.request_id"]`） |
  | `tenant_id`・`user_id` | 要求は `GraphqlController`（認証の後）。ジョブは `ApplicationJob#perform_now`（付帯情報のテナント。`Contracts::EventJob` は宛先テナント） |
  | `graphql_operation` | `GraphqlController`（`operationName`。無ければ `anonymous`） |
  | `job_id`・`job_class`・`queue` | `ApplicationJob#perform_now` |
  | `event_id`・`event_name` | `ApplicationJob#perform_now`（`Contracts::EventJob` の付帯情報） |
  | `correlation_id`・`causation_id` | 要求は `Platform::RequestContext`、ジョブは `ApplicationJob#perform_now`（下の「相関 ID と因果 ID」） |

  文脈を設定する区間は、Rails がイベントを出す区間を含めなければならない。Rails 8.1.4 は、`action_controller.request_started` を `before_action` より前の `process_action` の入口で出す。`active_job.started` は perform のコールバックより前の `_perform_job` で、`active_job.completed`・`retry_scheduled`・`discarded` は `perform_now` の計装の中で出す。コントローラの中で設定した文脈は `request_started` に付かず、`around_perform` で設定した文脈はジョブのこれらのイベントに付かない。
  - **要求**：`Platform::RequestContext` は、`Rails::Rack::Logger` の直前（`ActionDispatch::RequestId` の後、`ActionDispatch::Executor` の内側）で、`request_id` と相関 ID を設定する。セッションはこの位置より内側で読まれるので、`request_started` に付くのは `request_id` と相関 ID だけで、`tenant_id`・`user_id`・`graphql_operation` は `request_completed` から付く。
  - **ジョブ**：`ApplicationJob` は `perform_now` を上書きし、`super` の前に文脈を設定する。ワーカー（`ActiveJob::Base.execute` から `perform_now`）と、直接の `perform_now` の両方がここを通り、Active Job の計装と例外の処理の外側にあたる。文脈の値は、業務の引数ではなく、ジョブが引数とは別に持つ付帯情報（下の「付帯情報の運び方」）から読み、ここで引数を復元しない。Active Job の private のメソッドも呼ばない。Rails 8.1.4 は、引数の復元を `super` の中の、再試行・破棄の処理と計装の内側で行う。先に復元すると、復元の失敗（`ActiveJob::DeserializationError`）が `retry_on`・`discard_on`・`after_discard` を通らず、`active_job.completed` も出ない。

  `GraphqlController` は、スキーマを実行する前に文脈を設定する。`Rails.event` の文脈は Fiber のストレージにあり、Dataloader が作る Fiber は、作られた時点の値を写して持つ。Fiber の中で設定した値は、親に戻らない。
- 文脈の後始末：Rails は、executor で包まれた処理（Web の要求と、ワーカーが動かすジョブ）の終わりに、`Rails.event` の文脈を空にし、エラー通知の文脈（`ActiveSupport::ExecutionContext`）を始まりの push と対で pop する（入れ子を許さない既定では、push も pop も空にする）。テストの example と、`perform_now` で直接動かすジョブは executor で包まれないので、文脈が次の処理へ持ち越される。そこで、`ApplicationJob#perform_now` は、実行の前の `Rails.event.context` を退避して `ensure` で戻し、エラー通知の文脈も丸ごと退避し、項目の集合ごとジョブの項目に置き換えて、`ensure` で丸ごと戻す（`guides/config.md`「文脈の後始末」）。`spec/support/log_context.rb` は、各 example の後で `Rails.event.clear_context` と `ActiveSupport::ExecutionContext.clear` を呼ぶ。
- 相関 ID と因果 ID：
  - **相関 ID**（`correlation_id`）：一連の処理の始まりで 1 つ決め、最後まで同じ値を運ぶ。利用者のリクエストでは、`request_id` を相関 ID にする。
  - **因果 ID**（`causation_id`）：いまの処理を直接引き起こしたものの ID。リクエストでは空、イベントの受け手では届いたイベントの `event_id` である。
  - **イベントの付帯情報**：`Contracts.publish` は、イベントごとに `event_id`（UUIDv7）を作る。それと、イベントの名前、いまの文脈の相関 ID・因果 ID、発行元のテナント ID、宛先テナント ID、発行時刻（`published_at`）を、付帯情報としてジョブに持たせる。ペイロードにも引数にも入れない。受け手のジョブは付帯情報から文脈を設定する。受け手の中で発行するイベントは、同じ相関 ID と、因果 ID として受け手が受け取ったイベントの `event_id` を持つ。
  - **イベント以外のジョブ**：`ApplicationJob` は、ジョブを作った時点（`initialize`）の相関 ID とテナント ID を付帯情報に入れ、実行時に文脈へ戻す。`Contracts.publish` は、ジョブを作った後、登録の前に、付帯情報をイベントのものに置き換える。
  - **付帯情報の運び方**：`ApplicationJob` は付帯情報を属性に持ち、`serialize` が返すハッシュのトップレベルの項目（`"app_metadata"`）に入れ、`deserialize` で `super` の後に読み戻す。Rails の `deserialize` は、引数を `serialized_arguments` に直列化したまま持ち、`perform_now` の中まで復元しないので、`perform_now` の上書きは引数を復元せずに付帯情報を読める。再試行の登録は同じジョブを `serialize` し直すので、付帯情報も引き継がれる。項目の無いジョブ（M18 より前に登録されたもの）は、付帯情報の文脈を設定せずに動かす。付帯情報のテナントは、ログとエラー通知の文脈にだけ使う。ジョブが開くテナントは、これまでどおり引数とペイロードから決める（M4、`adr/005` 決定 3）。

  これで、発注側の `placePurchaseOrder` のリクエスト → 「発注登録」 → 受注側の ACL → 「受注確定」 → 購買の受け手、の全ログが同じ相関 ID を持つ。テナントは途中で変わるので、相関 ID でログを引けるのは運用者だけで、テナントの利用者には相手側のログを見せない。
- アプリが出すイベント：GraphQL の操作の終わりに `graphql.operation_completed`（操作名・結果の種類・ユーザーエラーのコード・時間）、受け手の終わりに `contracts.event_handled`（イベント名・受け手・配送の遅れ = 受け手の始まりの時刻 − `published_at`）。
- 書かないもの：
  - **個人情報と秘密**：メールアドレス・氏名・パスワード・セッションの Cookie・API キー・Webhook の署名。ペイロードには ID・コード・件数・時間だけを入れ、自由記述（取消の理由・在庫調整の理由）も入れない。
  - **GraphQL の変数とクエリの本文**：変数はキーの一覧だけを書き、クエリの本文は SHA-256 の要約だけを書く（上の表の `action_controller.request_started`）。
  - **ジョブの引数と例外のメッセージ**：上の表のとおり書かない。
  - **SQL**：`active_record.sql` はデバッグのイベントで、開発でだけ出る。本番は出さない。
  - **ハッシュでないペイロード**：`Rails.event` は、ハッシュのペイロードにだけ `filter_parameters` を掛ける。ハッシュでないペイロードが購読者に届くのは、イベントのオブジェクトを `notify` に渡したときである。購読者は、それを例外にする。Rails は `Rails.event.raise_on_error` を `consider_all_requests_local` から決める（開発とテストで真、本番で偽）ので、購読者の例外は、開発とテストでは呼び出し元まで上がり、本番ではエラー通知に送られて行が書かれない。この 2 つの設定を変えない。`filter_parameters` に `name` を足すと `item_name`・`operation_name` まで消えるので、氏名は「ペイロードに入れない」規則で守る。
- `spec/contracts/correlation_spec.rb`：発注 → イベントを流す → 受注確定 → 購買の受け手、の全ログ行が同じ相関 ID を持ち、受け手の行の因果 ID が届いたイベントの `event_id` であることを確かめる。全ログ行には、Rails の `action_controller.request_started`・`active_job.started`・`active_job.completed` を含める。ログは、テストの中で購読者を足して集める。
- `spec/jobs/log_context_spec.rb`：ジョブを直接の `perform_now` と、ワーカーの経路（`ActiveJob::Base.execute(job.serialize)`）で動かし、どちらでも次を確かめる。`active_job.started`・`active_job.completed`（成功と失敗）・`active_job.retry_scheduled` のイベントと本体の中で、付帯情報とテナントから文脈が設定されている。エラー通知の文脈にテナント ID が入る。実行の後は実行の前の文脈に戻る。さらに、ワーカーの経路で引数の復元に失敗するジョブ（消したレコードの GlobalID を引数に持つもの）を、`discard_on ActiveJob::DeserializationError`・`retry_on ActiveJob::DeserializationError`・どちらも無し、の 3 通りで動かす。破棄では `after_discard` が呼ばれて `active_job.discarded` が出る。再試行では `active_job.retry_scheduled` が出て、登録し直したジョブが同じ付帯情報を持つ。どちらも無しでは例外が呼び出し元へ上がる。3 通りとも `active_job.completed` が出て、これらのイベントと `after_discard` の中で付帯情報から文脈が設定されている。
- `spec/requests/log_hygiene_spec.rb`：`Platform::Logging.configure!` を通したテストの環境で、2 つの出口を `StringIO` に向けて集める。文字列のログは、`Platform::Logging.build` のロガーを本番の既定と同じ `info` の水準で `Rails.logger.broadcast_to` に足して集め、終わりに `stop_broadcasting_to` で外す。イベントは購読者を足して集める。流すのは、ログイン、メールアドレス・パスワード・自由記述の理由を値に含む mutation、変数を伴う GraphQL の要求、URL の `query`・`variables` に禁止の値を入れた `/graphql` への要求、例外のメッセージに禁止の値を含めて失敗する要求とジョブ、イベントの配送である。集めた全行が JSON として読め、どの行にも禁止の値が現れないことを確かめる。イベントのオブジェクトを `Rails.event.notify` に渡すと例外になることも確かめる。

**判断**：ログの出口に `Rails.event` を使うか、lograge のような gem で文字列のログを JSON にするか

- **既定の推奨**：`Rails.event` を使う。Rails 8.1 の計装がそのまま構造化イベントになり、ハッシュのペイロードに `filter_parameters` が掛かり、文脈が Web の要求とワーカーのジョブの単位で空に戻る。メトリクス（M30）も同じイベントから作れる。
- **裏返る条件**：Rails の構造化イベントの名前やペイロードが版上げのたびに変わり、追従の手間がログの価値を上回る → 購読者に、名前を固定の一覧へ写す層を足す。それでも足りなければ、OpenTelemetry のログに移る。
- **撤退コスト**：小さい。購読者を外せば、Rails の文字列のログに戻る。高くつくのは、アプリのコードが `Rails.logger.info` の文字列に文脈を埋め込んだ後で、構造化に移ることである。

**完了条件**

```sh
bundle exec rspec spec/contracts/correlation_spec.rb spec/requests/log_hygiene_spec.rb spec/jobs
```

ログの検査は rspec の中にあるので、`config/ci.rb` と `.github/workflows/ci.yml` の rspec のステップで毎回流れる。

rspec はテストの環境の構成だけを通るので、開発の環境の構成は次の 2 つで確かめる。

```sh
bin/rails middleware | grep -A1 'Platform::RequestContext'   # 開発の環境：次の行が Rails::Rack::Logger
```

開発の環境で `bin/dev` と `bin/jobs` を動かして発注を 1 件登録し、`grep <相関 ID> log/events.log` で、その要求の `action_controller.request_started` の行と、2 社のイベントの配送（`active_job.started`・`contracts.event_handled`）の行が、同じ相関 ID で並ぶことを、手で確かめる。

**実装する文書の節**：`decisions.md` 2 章（テナント文脈のログへの伝播）、`adr/005` 決定 3、`data-model.md`「イベントの受け口と冪等キー」の付帯情報

**文書に残すこと**：`adr/005` 決定 3 に、ジョブが引数とは別に、直列化のトップレベルの項目として付帯情報を持つことを足す。`data-model.md`「イベントの受け口と冪等キー」の「ジョブの引数は、ペイロードとは別に付帯情報を持つ」を、引数ではなく直列化の項目に持つ形に直す。止めたフレームワークの文字列のログの経路（購読・`Rails::Rack::Logger`・`ActionDispatch::DebugExceptions`）、イベントごとに書く項目の表、全環境で挿入する `Platform::RequestContext` と、本番とテストだけが呼ぶ `Platform::Logging.configure!`、文脈を設定する位置、ログの出力先を `guides/config.md` に書く。

## M19 監査ログ

**目的**：相手テナントに効果が及ぶ書き込みは、必ず監査ログに残る。記録は mutation の基底クラスとイベントのジョブの基底クラスが行い、個々の操作で手書きしない（`decisions.md` 2 章「監査」）。監査ログは追記だけで、書き換えも削除もできない。

`decisions.md` 2 章は「操作者のテナントとデータの所有テナントが異なる書き込み」を監査の対象にする。本デモには相手テナントの名義で書く経路が無い（`context-map.md`「テナントと所有」）ので、対象を「相手テナントに効果が及ぶ書き込み」に置き換える。相手テナントへのイベントを出す操作、相手から見えるデータ（カタログ・取引関係）を変える操作、相手の操作で自社のデータが変わったこと（イベントの受信）がこれに当たる。同じテナントの中で受け渡すイベント（`allocateSalesOrder` が出す「出荷可能」など）は、相手テナントに効果が及ばないので対象にしない。

**作るもの**

- 表 `audit_logs`（`packs/platform`）と、追記だけにする仕組み（`data-model.md`「監査ログ（`platform`）」）。行のトリガーは `TRUNCATE` で動かないので、`TRUNCATE` を拒む文単位のトリガーも置く。
- mutation の宣言：`Mutations::BaseMutation` に `audit "<action>", target: ..., counterparty: ...` か `audit_exempt reason:` を必須にする。宣言が無ければ、認可の宣言と同じく、開発とテストで例外、本番で拒否する。`target:` と `counterparty:` はラムダで、`perform` が成功の値を返した後に、成功の値（`result`）・`find_target` で引いた対象（`target`）・入力（`input`）を受け取って評価する。複数の相手に効果が及ぶ操作は、相手を列挙せず、相手を空にする。1 回の操作で書く行は 1 行である。M19 の時点の mutation の宣言は次の表のとおりで、`allocateSalesOrder`・`adjustStock`・`createShippingInstruction`・`cancelShippingInstruction` は `audit_exempt`（効果が自社の中で閉じる）にする。

  | mutation | action | 対象 | 相手 |
  |---|---|---|---|
  | `establishPartnership` | `partnership.establish` | 成功の値の取引関係 | その取引関係の発注側 |
  | `revokePartnership` | `partnership.revoke` | 対象の取引関係 | その取引関係の発注側 |
  | `grantPermission` | `partnership.grant_permission` | 対象の取引関係 | その取引関係の発注側 |
  | `withdrawPermission` | `partnership.withdraw_permission` | 対象の取引関係 | その取引関係の発注側 |
  | `saveItem` | `item.save` | 成功の値の品目 | 空（カタログを見る全相手に及ぶ） |
  | `setItemPublished` | `item.set_published` | 対象の品目 | 空（カタログを見る全相手に及ぶ） |
  | `registerPartMapping` | `part_mapping.register` | 成功の値の対応表の行 | 入力の `customerTenantId`（確定させる受注は、すべてこの相手の受注である） |
  | `placePurchaseOrder` | `purchase_order.place` | 成功の値の発注 | 入力の `supplierTenantId` |
  | `postShipment` | `shipment.post` | 成功の値の出荷依頼から引き直した出荷実績（OI-38） | 出荷依頼の発注側 |

- 監査の行とコミットの単位：基底 mutation は、`perform` が成功の値を返したときだけ、公開 API が戻った後に、リクエストのトランザクションの中で 1 行を書く。リクエストのトランザクションは `GraphqlController` が開き、次のように閉じる（`graphql-schema.md`「1 回のリクエストがたどる道」）。
  - **ユーザーエラー**：失敗を返した公開 API は、自分のセーブポイントまで書き込みを戻している。基底 mutation は監査の行を書かない。リクエストはコミットされるので、同じリクエストで先に成功した mutation の業務の行と監査の行は残る。
  - **トップレベルのエラーと例外**：`GraphqlController` がリクエスト全体を戻す。先に成功した mutation の業務の行・監査の行・イベントのジョブも一緒に戻る。監査の行の INSERT が失敗したときも、例外として全体が戻る。
- イベントの受信：`Contracts::EventJob` が、受け手の `handle` を終えた後、同じトランザクションで `event.received` を 1 行書く。書くのは、付帯情報の発行元のテナントと宛先テナントが違うときだけである。操作者は `system`、因果 ID は `event_id`、相手テナントは発行元のテナントである。同じイベントの 2 回目の配送では書かない（一意索引と `ON CONFLICT DO NOTHING`）。受け手が例外を投げれば、受け手の書き込みと一緒に戻る。
- 列挙テスト：`spec/graphql/authorization_declarations_spec.rb` を広げ、スキーマにある全 mutation が監査の宣言を持ち、宣言の種類（`audit` か `audit_exempt`）が `graphql-schema.md`「監査ログ」の表の行と一致することを確かめる。スキーマにある mutation が表に無ければ落ちる。表にあってスキーマにまだ無い mutation（後のマイルストーンで作るもの）は比べない。
- GraphQL：`viewer.auditLogs`（`admin` だけ。`graphql-schema.md`「監査ログ」）。到達可能性のテストに「`Viewer` からたどれる型は `shared` だけである」を足し、入口の行列に行を足す。
- 保存期間を過ぎた行の削除：所有ロールの rake タスク `audit:purge`。所有ロールの資格情報を持つ運用の工程で、月に 1 回流す。Web とワーカーには資格情報が無いので流せない。
- 競合テストの後始末：`concurrency` の置き場のテスト（M16）は、作った業務の行を所有ロールで消すが、監査の行と、監査の行が指すテナントとユーザー（`actor_user_id`）は消さずに残す。監査の行は所有ロールでも消せない（`TRUNCATE` も、それを拒むトリガーで消せない）。監査の行の所有テナントは、`audit_logs.owner_tenant_id` の外部キーで消せない。相手テナント（`counterparty_tenant_id`）は外部キーを張らない ID の参照なので消せるが、監査の行が無いテナントを指さないように、これも残す。担当者は、既存の競合テストの後始末からテナントの DELETE を外す。
  - 残す行の一意の値（テナントの `code`・`partner_code`、ユーザーの `email`）は、すべて乱数で作る。factory の `sequence` はプロセスごとに 1 から数え直すので、同じ DB に 2 回目を流すと、残った行と一意の制約で衝突する。残った行は乱数の値で分かれるので、他の example から見えない。
  - 監査の行を作る競合を 1 本含める：`spec/concurrency/post_shipment_audit_spec.rb` は、同じ出荷依頼の `postShipment` を 2 つの接続から GraphQL を通して同時に送り、成立した 1 件だけが監査の行を持つことを確かめる。公開 API を直接呼ぶ競合テストは監査の行を作らないので、これが無いと、下の完了条件の 2 回の実行が監査の制約を通らない。
- `spec/db/audit_logs_spec.rb`：アプリのロールの UPDATE と DELETE が権限で拒まれる。所有ロールでも、UPDATE と、保存期間の中の行の DELETE と、`TRUNCATE` がトリガーで拒まれる。
- `spec/requests/audit_spec.rb`：次の場合ごとに、業務の行・監査の行・イベントのジョブの残り方を確かめる。
  1. `placePurchaseOrder` の成功で監査の行が 1 行、`NOT_PERMITTED` で 0 行
  2. 1 つの要求で 2 つの mutation を送り、先が成功し、後がユーザーエラー：先の業務の行・監査の行・イベントのジョブが残り、後の分は何も残らない
  3. 1 つの要求で、先の mutation が成功し、後がトップレベルのエラー（`FORBIDDEN`）：どれも残らない
  4. 監査の行の INSERT が失敗する：業務の行もイベントのジョブも残らない
  5. 受け手が例外を投げる：`event.received` の行も受け手の書き込みも残らない。再実行で成功すると 1 行になる
  6. 受注側に「受注確定」までのイベントの受信の行ができ、同じイベントを 2 回流しても増えない。同じテナントの中のイベント（「出荷可能」）では行ができない
  7. 発注側の行と受注側の行が、同じ相関 ID を持つ

**判断**：監査の記録をどこに置くか

- **既定の推奨**：mutation の基底クラスと、イベントのジョブの基底クラスの 2 か所に置く。本デモで書き込みが起きる入口は、この 2 つだけだからである。公開 API の操作には共通の基底クラスが無く、記録を置くと操作ごとに手書きになる。
- **裏返る条件**：GraphQL の mutation 以外の書き込みの入口（管理画面・外部向けの API・運用の手順のスクリプト）が増える → 公開 API の操作に宣言を移し、入口を問わず記録する。
- **撤退コスト**：中程度。宣言は mutation ごとに 1 行なので移すのは機械的だが、記録の粒度（mutation 単位か、公開 API の操作単位か）が変わり、移す前と後の行を並べにくくなる。

範囲外：相手テナントへの監査ログの写し（発注側が、受注側の受信の記録を見ること）、月ごとの表の分割。

**完了条件**

```sh
bundle exec rspec spec/db/audit_logs_spec.rb spec/requests/audit_spec.rb spec/graphql spec/matrix
bundle exec rspec --tag concurrency && bundle exec rspec --tag concurrency   # 監査の制約を有効にしたまま、同じテスト DB で続けて通る（0 件なら失敗する）
```

2 回の実行には `spec/concurrency/post_shipment_audit_spec.rb` が含まれ、1 回目で監査の行とテナントが残った DB に 2 回目を流す。

**実装する文書の節**：`decisions.md` 2 章「監査」、`data-model.md`「監査ログ（`platform`）」、`graphql-schema.md`「監査ログ」

**文書に残すこと**：`decisions.md` 2 章「監査」の対象の定義を、目的の段落のとおり「相手テナントに効果が及ぶ書き込み」に直し、記録する場所を mutation の基底クラスとイベントのジョブの基底クラスにする。mutation ごとの action・対象・相手の表と、同じテナントの中のイベントを記録しない規則を `graphql-schema.md`「監査ログ」に移す。監査の対象を変えたら、その表を同じ変更で直す。`TRUNCATE` を拒むトリガーを `data-model.md`「監査ログ（`platform`）」の追記だけにする仕組みに足す。競合テストの後始末の規則を `guides/testing.md` に書く。

## M20 GraphQL スキーマの破壊的変更の検出

**目的**：GraphQL のスキーマの変更が、PR の差分として読める。クライアントを壊す変更（フィールドの削除・型の変更・必須の引数の追加など）は、先に非推奨にしてからでないと CI を通らない（`graphql-schema.md`「スキーマの変更と非推奨」）。

**作るもの**

- `lib/tasks/graphql.rake`：`GraphQL::RakeTask.new(schema_name: "FactoryOpsSchema")`。`bin/rails graphql:schema:idl` が、リポジトリの根に `schema.graphql` を書く。
- `spec/graphql/schema_dump_spec.rb`：`FactoryOpsSchema.to_definition` が `schema.graphql` と一致することを確かめる。型を変えて書き直しを忘れると落ちる。
- graphql-schema_comparator（`~> 1.2`）を development と test のグループに入れる。
- 互換の判定（`lib/schema_compat.rb`）：基準の SDL と作業中の SDL と例外の一覧を受け取り、`GraphQL::SchemaComparator.compare` の結果の変更ごとに、通すか落とすかを返す。変更は、比較器の変更のクラス名（`FieldRemoved` など）と、スキーマの座標（変更の `path`。`PurchaseOrder.lines` の形）で識別する。判定の規則と当てる順は `graphql-schema.md`「互換の判定」の表にある（削除・型の変更・必須の追加と既定値を外す変更・上に当たらない変更の 4 つ）。

  型の変更と必須の追加で落ちる変更は、担当者が、新しい型や引数を持つフィールドを足し、古いフィールドを非推奨にしてから、別の PR で消す（`graphql-schema.md`「スキーマの変更と非推奨」）。非推奨のフィールドの型をその場で変えても通らない。
  - 例外の一覧（`docs/graphql/breaking-changes.yml`）：規則で落とした変更は、例外の一覧に同じ変更のクラス名と座標の行があるときだけ通す。秘密を漏らすフィールドを非推奨を経ずに消すときは、削除の規則で落ちた `FieldRemoved` をこの行で通す。行は `change`・`path`・`reason` を持ち、`reason` が空の行があれば、一覧の読み込みで失敗する。クラス名か座標が違う行は、その変更を通さない。どの変更にも当たらない行は、警告として一覧に出す。
- `bin/check-schema-compat`：基準（環境変数 `BASE_REF`、既定は `origin/main`）と HEAD の分岐点の `schema.graphql` と、作業中の `schema.graphql` を互換の判定に渡し、落とす変更が 1 つでもあれば失敗する。分岐点に `schema.graphql` が無いときも失敗する。結果を標準出力と `$GITHUB_STEP_SUMMARY` に書く。
- `spec/graphql/schema_compat_spec.rb`：小さな新旧の SDL（`spec/fixtures/graphql/schema_compat/`）を互換の判定に渡し、全分岐を確かめる。非推奨でないフィールドの削除・非推奨でない enum の値の削除（出力にだけ使う enum と、入力に使う enum の両方）・非推奨のフィールド・引数・enum の値の削除・型の削除・フィールドの型の変更（非推奨のフィールドを含む）・比較器が非破壊とする型の変更（出力の非 null 化）・必須の引数の追加・必須の入力項目の追加・enum の値の追加・例外の行の一致・非推奨でないフィールドの削除を例外の行で通す場合・クラス名か座標の違う例外の行・`reason` の無い例外の行・どの変更にも当たらない例外の行・基準に `schema.graphql` が無い場合である。
- CI：`.github/workflows/ci.yml` の lint のジョブで、`actions/checkout` を `fetch-depth: 0` にして基準を取れるようにし、`bin/check-schema-compat` を流す。基準は、PR では向き先（`origin/<base_ref>`）、main への push では push の前の先端（`github.event.before`）にする（`graphql-schema.md`「互換の判定」）。`config/ci.rb` にも同じステップを足す。
- 初回の導入：最初は基準に `schema.graphql` が無く、比べられない。担当者は M20 を 2 つの PR に分ける。1 つ目の PR は、`schema.graphql`・書き出しの検査・互換の判定と spec・`bin/check-schema-compat` を入れ、CI のステップは足さない。2 つ目の PR は、1 つ目が main に入った後に、CI のステップを足す。

**判断**：比較に graphql-schema_comparator を使うか

- **既定の推奨**：使う。graphql-ruby の手引き（Testing の Schema structure）が挙げる Ruby の比較器で、依存する graphql の版の範囲に 2.6 が入る。
- **裏返る条件**：更新が止まったまま、graphql-ruby の 3 系で動かなくなる → Node の graphql-inspector を CI でだけ使うか、`GraphQL::Schema` の反射で要る検査（削除・型の変更・必須の追加）だけを自作する。
- **撤退コスト**：小さい。互換の判定の中を差し替えるだけで済み、`schema.graphql` とその書き出しの検査、互換の判定の spec は残る。

> graphql-schema_comparator の最新は 1.2.1（2023 年 10 月の公開）で、依存する graphql の版の範囲は `>= 1.10, < 3.0` である。

**完了条件**

```sh
bin/rails graphql:schema:idl && git diff --exit-code schema.graphql
bundle exec rspec spec/graphql/schema_dump_spec.rb spec/graphql/schema_compat_spec.rb
BASE_REF=origin/main bin/check-schema-compat
```

**実装する文書の節**：`graphql-schema.md`「スキーマの変更と非推奨」

**文書に残すこと**：通す変更の規則と、例外の一覧の書式（`change`・`path`・`reason`）を、`graphql-schema.md`「スキーマの変更と非推奨」に書く。

## M34 依存の更新と使っていない部品の削除

**目的**：使っていない Rails の部品と gem を残さず、保守の続く Ruby で動かす。読む人や AI が、読み込まれた部品を見て使える前提で設計しない。依存を上げる前に、本番で止めているフレームワークの文字列のログ（`guides/config.md`「止めたフレームワークの文字列のログ」）が、新しい版で漏れないことを確かめる。

**作るもの**

1. 止めたログの経路の調べ直し（改善の候補 IB-14）：上げた後の Rails・Solid Queue・Ruby で、値を文字列で書く購読とミドルウェアが、止めた 5 つの経路のほかに増えていないかを確かめる。購読者の一覧とミドルウェアの並びを上げる前と後で比べ、ログの衛生の spec を新しい版で流す。`spec/platform/logging_spec.rb` の拒否の一覧（外した購読とミドルウェアが無いことを見る example）は、新しい版で増えた購読者を捕まえないので、比べるのは購読者の一覧とミドルウェアの並びそのものである。拒否の一覧を、原則出さない許可の形に変えるかを決め、決めたことと比べた結果を `guides/config.md`「止めたフレームワークの文字列のログ」に書く（複数の案を比べたなら ADR にする）
2. 使っていない部品を外す：`config/application.rb` の Active Storage・Action Mailbox・Action Text・Action Cable の読み込み、`config/environments/*.rb` の `active_storage.service` と Action Cable の生成時のコメント、`config/storage.yml`、`config/cable.yml`、kamal と image_processing の gem と Gemfile のその説明のコメント、Dockerfile の libvips と冒頭の Kamal の説明、`.dockerignore` の `/.kamal`。thruster（Dockerfile の起動の命令が使う）と Action Mailer（通知の送り方を `adr/007` が決める）は残す
3. 外した部品が読み込まれないことを確かめる spec（`spec/platform/framework_loading_spec.rb`）：テストの環境の起動の後に、`ActiveStorage::Engine`・`ActionMailbox::Engine`・`ActionText::Engine`・`ActionCable::Engine` が定義されておらず、`ActionMailer::Base` が定義されていることを確かめる。外す前に書いて落ちることを見る
4. Ruby を 3.4 の最新の patch に上げる：`.ruby-version` と Dockerfile を変える（CI は `.ruby-version` を読む）。gem は Gemfile の版の制約を変えずに `bundle update` で上げ、上げる前と後の Rails・Solid Queue の版を作業 1 の比べる対象として PR の本文に書く。上げる前に、3.3.3 で `RUBYOPT=-W:deprecated` を付けて全件を流し、警告の件数を PR の本文に書いておく
5. Ruby の版を書いた文書を、上げた版に直す：この文書の「環境」の表と `handoff.md`「開発環境」
6. 依存の向きの表と `package.yml` の一致を確かめる spec（`spec/packwerk/dependency_table_spec.rb`）：`context-map.md`「疎結合を守る規則」の依存の向きの表を読み、ルートパッケージと `packs/*` の各 `package.yml` の `dependencies` と、パッケージの集合と依存先の集合が一致することを確かめる。表の括弧の注記（`PublishedCatalog` だけ）は依存先の名前から外して比べ、注記の範囲は `spec/packwerk/purchasing_uses_only_published_catalog_spec.rb` に任せる。表の「すべて」は、ルートパッケージ以外のすべてのパッケージとして読む。表はこの計画レビューでいまの `package.yml` に合わせたので、書いた時点で通る。表の行の依存先を 1 つ消すと落ち、`package.yml` に依存を 1 つ足すと落ちることを確かめてから戻す（OI-58）

**判断**：Ruby を 3.4 へ直接上げるか

- **既定の推奨**：直接上げる。文字列を比べる spec に `Hash#inspect` の表記に頼るものは無く、変える設定は `.ruby-version` と Dockerfile だけである（版を書いた文書は作るもの 5 で直す）
- **裏返る条件**：3.4 で全件が通らない gem があり、すぐに直せない → 3.3 系の最新の patch にとどめ、3.4 は 3.3 系の保守が終わる前に別に上げる。とどめたときも作るもの 5 の文書を、とどめた版に直す
- **撤退コスト**：小さい。`.ruby-version` と Dockerfile と作るもの 5 の文書を戻すだけで済む

**完了条件**

```sh
bundle exec rspec spec/platform/framework_loading_spec.rb spec/packwerk/dependency_table_spec.rb
bundle exec rspec                                                # 全件。本番の環境の起動は spec/platform/logging_spec.rb の子のプロセスが確かめる
RUBYOPT=-W:deprecated bundle exec rspec 2> tmp/deprecated.log    # 終了コード 0
test "$(grep -cE "^$PWD/(app|packs|lib|config|bin)/[^:]+:[0-9]+: warning:" tmp/deprecated.log || true)" -le <上げる前の件数>
git grep -nE "active_storage|action_mailbox|action_text|action_cable|image_processing|kamal" -- config app Gemfile Dockerfile; test $? -eq 1   # 一致が 0 件（git grep の 1）。実行の誤り（128）は落とす
test "$(ruby -e 'print RUBY_VERSION')" = "$(cat .ruby-version)"
bin/bundler-audit
```

比べる警告は、リポジトリのコード（spec を除く）から出たものに限る。Ruby 3.4 は `-W:deprecated` で文字列の書き換えの警告（chilled string）を新しく出し、gem の中から出る警告まで数えると、上げる前と後の件数を比べられないからである。`RUBYOPT` は子のプロセスにも引き継がれるので、子の標準エラーが空であることを確かめる spec が警告で落ちたら、その spec の子のプロセスの環境から `RUBYOPT` を外す。上げる前の件数も同じ数え方で取る。

保守の続く Ruby かどうかは、コマンドで判定しない。上げた版の保守の状態（ruby-lang.org の「Ruby の各ブランチのメンテナンス状況」）を、PR の本文に引く。

**実装する文書の節**：`guides/config.md`「application.rb で変えたこと」「使っていない機能の設定」「止めたフレームワークの文字列のログ」、`README.md`「開発環境」

**文書に残すこと**：外した部品と残した部品の理由を `guides/config.md` に書く。止めたログの経路の調べ直しの結果を、`guides/config.md`「止めたフレームワークの文字列のログ」に書く。

## M35 分岐の網羅率の警告

**目的**：PR が足した行の分岐のうち、どの example も通らないものを、実装レビューの前に一覧にする。確かめる example の抜け（サイクル 01 で 4 件）のうち、分岐を一度も通らなかったものを、レビューだけに頼らずに見つける。網羅率は「実行したか」だけを見て「確かめたか」は見ない。通った分岐の別の入力（サイクル 01 の M20 の X1）も拾わない。そのため失敗にはせず警告にとどめる。

**作るもの**

- 計測：`spec/spec_helper.rb` は、環境変数 `COVERAGE=1` のときだけ、ファイルの先頭（Rails とアプリを読み込む前）で標準の `Coverage` を分岐で始め、rspec の終わりに結果を `tmp/coverage.json` に書く。gem は足さない。結果は、計測の対象のファイルごとに、分岐の座標（種類・開始の行と列・終わりの行と列）と通過の回数の組を配列で持つ
- 計測の範囲：計測の対象は、rspec のプロセスが読み込んだ `app/`・`packs/*/app/`・`lib/` の Ruby のファイルである。子のプロセス（`spec/platform/logging_spec.rb` の本番の起動、`spec/bin` が流す `bin/` のスクリプト）は測らない。`bin/` のスクリプトと `config/`・`db/` は対象の外にする
- `bin/check-branch-coverage`：`tmp/coverage.json` と、基準の ref（`BASE_REF`、既定は `origin/main`）と HEAD の分岐点からの `git diff` を照らし、計測の対象のファイルの足した行か変えた行にある分岐のうち、どの example も通らないものを一覧にする。差分にある計測の対象のファイルが計測の結果に無いとき（どの example も読み込まなかった）は、「計測なし」としてファイルごとに一覧に出し、未通過なしとして扱わない。標準出力と `$GITHUB_STEP_SUMMARY` に書き、行ごとに GitHub の警告の注釈を出す。終了コードは 0 にする。`tmp/coverage.json` が無いか読めないときは、終了コード 1 で失敗する
- CI：test のジョブを履歴をすべて取る形（`fetch-depth: 0`）にし、既存の rspec のステップを `COVERAGE=1` で流す形に置き換えて（2 回流さない）から `bin/check-branch-coverage` を流す。基準は、lint のジョブの `bin/check-schema-compat` と同じ式で契機ごとに決める。PR では向き先（`origin/<base_ref>`）、main への push では push の前の先端（`github.event.before`）である。`origin/main` を既定のまま使うと、main への push では分岐点が HEAD 自身になって差分が空になり、積み重ねた PR では main からの累積の差分になるからである。`config/ci.rb` にも足す
- いま通っていない公開 API の失敗の経路 8 か所の example：出荷の指示（`Fulfillment::Instructions`）の `create` と `cancel` の `NOT_FOUND`（2 か所）、計上（`Fulfillment::Shipping.post`）の `NOT_FOUND`（1 か所）、受注の引当（`Sales::OrderAllocation.allocate`）の取消済・出荷済の `CONFLICT`（1 つの `if` で、取消済と出荷済の 2 つの example を書く）、品目の保存（`Sales::Catalog`）の `NOT_FOUND`（1 か所）、イベントの受け手 3 つ（`Purchasing::SupplierEventReceiver`・`Sales::FulfillmentEventReceiver`・`Fulfillment::SalesEventReceiver`）の想定外のイベント（3 か所）
- `spec/bin/check_branch_coverage_spec.rb`：小さな計測の結果と差分を渡し、次を確かめる。足した行の未通過の分岐だけを一覧にする。足していない行の未通過と、通った分岐を出さない。差分にあって計測の結果に無いファイルを「計測なし」で出す。計測の対象の外のファイル（`bin/`・`config/`）を出さない。`tmp/coverage.json` が無ければ失敗する。あわせて、計測の結果を書く部分を、既知の未通過の分岐を持つ fixture で流し、その分岐の座標が結果に出ることを確かめる。全件を `COVERAGE=1` で流している間は同じプロセスで `Coverage` を始め直せないので、この部分は子のプロセスで流す

**判断**：計測と照合に gem（SimpleCov と undercover）を使うか

- **既定の推奨**：使わない。標準の `Coverage` と `git diff` を照らす自前のスクリプトにする。undercover は libgit2 のネイティブのビルド（rugged）に依存し、要るのは差分の行と未通過の分岐を照らすことだけである
- **裏返る条件**：照合の規則（名前の変わったファイル・子のプロセスの計測など）が増え、自前のスクリプトの保守が重くなる → SimpleCov（子のプロセスを含められる）と undercover に移す
- **撤退コスト**：小さい。計測の結果の形が同じなので、スクリプトを差し替えるだけで済む

**完了条件**

```sh
bundle exec rspec spec/bin/check_branch_coverage_spec.rb
COVERAGE=1 bundle exec rspec && BASE_REF=origin/main bin/check-branch-coverage   # 終了コード 0
```

公開 API の失敗の経路 8 か所は、M35 の差分に無い（足すのは spec だけ）ので、警告の一覧では確かめられない。`tmp/coverage.json` で、8 か所の分岐の通過の回数が 1 以上であることを確かめ、PR の本文に書く。

CI の test のジョブの要約に、PR の向き先からの差分の一覧が出る（M35 の PR 自身で確かめる）。

**実装する文書の節**：`guides/testing.md`（分岐の網羅率の警告の読み方を足す）、`guides/bin.md`

**文書に残すこと**：警告が出たときに、example を足すか、足さない理由を PR の本文に書くことを `guides/testing.md` に書く。警告が拾わないもの（通った分岐の別の入力、確かめの抜け、子のプロセス）も同じ節に書く。次のサイクルの振り返りで、警告の件数と、そのうち example を足した件数を数える。

## M21 取消依頼と審査

**目的**：発注側の取消は、受注側の承認でだけ成立する。審査中は出荷の指示と計上が止まる。

**作るもの**

- `cancellation_requests`・`cancellation_reviews`・`shipping_holds`、取消依頼・出荷停止・出荷停止解除・取消承認・取消却下・出荷取消のイベントと配送表の行
- 購買：`Purchasing::Ordering.request_cancellation`（`graphql-schema.md`「mutation の一覧」）、取消承認・取消却下の受け手（`Purchasing::SupplierEventReceiver` に足す）
- 受注：取消依頼の受け手 `Sales::PurchasingEventReceiver`（審査を作り、出荷停止を出す。出荷済みなら審査を作らずに自動で却下する）、`Sales::CancellationReviews.approve`・`reject`。承認は、引当の解除と受注の `cancelled_at` を同じトランザクションで行う受注の内部の取消の処理を使う。この処理は M22 の受注側の取消も使う
- 出荷：出荷停止・出荷停止解除・出荷取消の受け手（`Fulfillment::SalesEventReceiver` に足す）。出荷取消は、出荷依頼の `cancelled_at`・有効な出荷指示の取消・出荷停止の解除を行う。`Fulfillment::Instructions` と `Fulfillment::Shipping.post` は、解除されていない出荷停止のある受注で `CONFLICT` を返す
- `requestPurchaseOrderCancellation`・`approveCancellationReview`・`rejectCancellationReview`（どれも `audit`。action・対象・相手の行を `graphql-schema.md`「監査ログ」の表に足す）
- 受注と発注の状況の「取消審査中」「取消依頼中」、出荷依頼の状況の「出荷停止中」の導出と `ShipmentRequestStatus` の `ON_HOLD`（OI-52）
- 読み取り：`PurchaseOrder.cancellationPending`・`cancellationRequests`、`SalesOrder.cancellationReviewPending`・`cancellationReviews`、型 `CancellationRequest`・`CancellationReview`、enum `CancellationOutcome`（`graphql-schema.md`）と、行列テストの行。受注側は `SalesOrder.cancellationReviews` で承認と却下に使う審査 ID を得る
- イベントの届く順の入れ替わり（OI-65）：出荷停止解除が出荷停止より先に、出荷取消が出荷可能より先に動いても、停止や出荷依頼が取り残されない受け手にする。決め方は M21 の着手のときに OI-65 で決める
- 付帯情報の無いイベントのジョブの扱い（OI-53）：`guides/config.md` は付帯情報の無いジョブも動くと書くが、`Contracts::EventJob` は受信の監査の行を書くときに付帯情報の項目を `fetch` するので、相手テナントからのイベントでは失敗する。イベントのジョブは付帯情報を必須とし、無ければ受け手の書き込みを戻して、付帯情報が無いことを示す専用の例外クラスで失敗させる。受信の監査の行を書けないまま受け手の書き込みだけを残すと、「相手テナントに効果が及ぶ書き込みは必ず記録される」（M19）が崩れるからである。`guides/config.md` の記述を、イベントのジョブとそれ以外のジョブに分けて直す

操作と状態の組みごとの結果は次のとおりである。失敗はどれも書き込みとイベントを残さない。

| 操作 | 状態 | 結果 |
|---|---|---|
| 取消依頼 | 回答待ちの取消依頼がある | `CONFLICT` |
| 取消依頼 | 発注が「取消済み」か「受注側により取消」 | `CONFLICT` |
| 取消依頼 | それ以外（出荷済みかどうかは購買では見ない） | 依頼を登録し、取消依頼を出す |
| 取消依頼の受け手 | 受注が出荷済みか取消済 | 審査を作らずに取消却下を出す（自動却下） |
| 取消依頼の受け手 | 受注がまだ無い（発注登録より先に届いた） | 例外で失敗し、再配送に任せる。既存の受け手（`find_by!`）と同じ |
| 承認・却下 | 審査が決着済み | `CONFLICT` |
| 承認 | 引当が消費済み（出荷の計上が先に成立した） | `CONFLICT`。担当者は却下する |

**完了条件**

```sh
bundle exec rspec packs/purchasing/spec/public/purchasing/cancellation_requests_spec.rb \
  packs/sales/spec/public/sales/purchasing_event_receiver_spec.rb packs/sales/spec/public/sales/cancellation_reviews_spec.rb \
  packs/fulfillment/spec/public/fulfillment/instructions_spec.rb packs/fulfillment/spec/public/fulfillment/shipping_spec.rb \
  packs/fulfillment/spec/models/fulfillment/shipment_request_status_spec.rb packs/fulfillment/spec/public/fulfillment/sales_event_receiver_spec.rb \
  spec/requests/cancellations_spec.rb spec/jobs/event_job_metadata_spec.rb
```

- 単体（`packs/*/spec/public`）：上の表の各行。出荷停止中の出荷指示の作成と計上が `CONFLICT` になる。出荷依頼の状況の導出表の 3 行目（解除されていない出荷停止があれば「出荷停止中」）と、出荷停止を解除した後に元の状況へ戻ること。新しい受け手に冪等の共有テスト（M7）を当てる。届く順を入れ替えた example（OI-65）
- 結合（`spec/requests/cancellations_spec.rb`）：依頼 → 停止 → 承認 → 発注が「取消済み」・出荷依頼が「取消済」の通し。依頼 → 却下 → 発注が元の状況に戻り、出荷停止が解除される通し。出荷済みの受注への依頼が自動で却下される通し
- `spec/jobs/event_job_metadata_spec.rb`：付帯情報（`app_metadata`）の無い形で直列化したイベントのジョブを `ActiveJob::Base.execute` に流すと、受け手の書き込みが残らずに、専用の例外クラスで失敗する（OI-53）。いまも `nil` への `fetch` で失敗して書き込みは戻るので、例外クラスで確かめないと実装の前から通る

**実装する文書の節**：`context-map.md`「取消の流れ」1〜4、`data-model.md`「出荷（`fulfillment`）」の出荷停止、`data-model.md`「状態は保存せず、時刻列から導出する」、`guides/config.md`「ログ」の付帯情報

**文書に残すこと**：操作と状態の組みごとの結果の表を `context-map.md`「取消の流れ」に書く。付帯情報の無いイベントのジョブの扱いを `guides/config.md` に書く。

## M22 受注側の取消と、取消と出荷の競合

**目的**：受注側は審査なしで取り消せる。同時に進んだ取消と出荷計上は、引当の行ロックでどちらか一方だけが成立する。

**作るもの**：`Sales::OrderCancellation.cancel`（M21 の受注の内部の取消の処理を使う）、受注取消のイベントと購買の受け手（`supplier_cancelled_at`）、`cancelSalesOrder`（`audit`。action・対象・相手の行を `graphql-schema.md`「監査ログ」の表に足す）。出荷取消のイベントと出荷の受け手は M21 のものを使う。審査の承認（M21）と受注側の取消は同じ受注の内部の取消の処理を通るので、下の競合テストが両方の経路の引当の行ロックを確かめる。

受注側の取消の結果は次のとおりである。

| 状態 | 結果 |
|---|---|
| 受注が出荷済みか取消済 | `CONFLICT` |
| 未決の取消の審査がある | `CONFLICT`。担当者は審査を承認して取り消す。審査中に受注側の取消を許すと、後から届く審査の決着と発注の 2 つの取消の時刻（`cancelled_at`・`supplier_cancelled_at`）が両立しうるからである |
| 引当が消費済み（計上が先に成立した） | `CONFLICT` |

**完了条件**

```sh
bundle exec rspec packs/sales/spec/public/sales/order_cancellation_spec.rb spec/requests/cancellations_spec.rb
bundle exec rspec spec/concurrency/cancel_vs_ship_spec.rb
```

- 単体（`order_cancellation_spec.rb`）：上の表の各行。取消で引当が解除され、受注取消と出荷取消が出る
- 結合（`spec/requests/cancellations_spec.rb` に足す）：`cancelSalesOrder` → イベントを流す → 発注が「受注側により取消」、出荷依頼が「取消済」、有効な出荷指示が取り消される。M21 の承認の通しとは別の example にする
- `spec/concurrency/cancel_vs_ship_spec.rb`（重要シナリオ S4 の取消）：2 つの接続で `Sales::OrderCancellation.cancel` と `Fulfillment::Shipping.post` を同時に走らせ、どちらか一方だけが成立することを、どちらが先にロックを取る順でも確かめる。このテストはトランザクションで包まない設定で動かし、作った行を後で消す。M21 では `Sales::OrderCancellation.cancel` が無いので、このテストは M22 で最初に落ちる

**実装する文書の節**：`context-map.md`「取消の流れ」の受注側の取消、`data-model.md`「取消と出荷の競合を止める場所」

**文書に残すこと**：審査中は受注側の取消を `CONFLICT` にすることを `context-map.md`「取消の流れ」に書く。

## M23 検収

**目的**：検収数量は出荷数量を超えない。検収は入荷 1 件に 1 回で、受注側へ 1 回だけ届く。

**作るもの**：`receipt_inspections`・明細、`inspection_records`、`Purchasing::ReceiptInspection.record`、検収完了のイベントと配送表の行、検収完了の受け手（M21 の `Sales::PurchasingEventReceiver` に足す）、受注の「検収済」と発注の「検収済」、`inspectInboundShipment`（`audit`。action・対象・相手の行を `graphql-schema.md`「監査ログ」の表に足す）、`InboundShipment.inspection`・`InboundShipmentLine.acceptedQuantity`

請求対象確定のイベントは M23 では足さない。受け手（M24）の無いイベントを配送表に載せると、配送表の spec（`spec/contracts/subscriptions_spec.rb`）が受け手の無い行で落ち、載せないと `Contracts.publish` が配送表に無いイベントで失敗するからである。イベント・配送表の行・受注の受け手からの発行・請求の受け手は、M24 で同時に足す。

検収の入力は次のとおりである。誤りはどれも `INVALID_INPUT` で、`path` に誤りの明細を示す。

- 入荷の全明細を 1 回で出す。明細の省略、同じ明細の重複、別の入荷の明細は誤りにする
- 検収数量は 0 以上・出荷数量以下の整数にする。0 は全量の不合格を表す
- 同じ入荷への 2 回目の検収は `CONFLICT` にし、検収完了を出さない
- 検収日は、検収を登録した日（自社の日付）にする

**完了条件**

```sh
bundle exec rspec packs/purchasing/spec/public/purchasing/receipt_inspection_spec.rb \
  packs/sales/spec/public/sales/purchasing_event_receiver_spec.rb spec/requests/inspections_spec.rb
```

- 単体（`receipt_inspection_spec.rb`）：上の入力の各誤り。出荷数量を超える検収が `INVALID_INPUT` になる。2 回目の検収が `CONFLICT` で、検収完了のジョブが 1 件のままである。検収の後に発注が「検収済」になる
- 単体（`purchasing_event_receiver_spec.rb`）：検収完了で受注が「検収済」になる（分納しないので、出荷実績は受注ごとに 1 件で、1 回目の検収完了がすべての出荷実績の検収になる）。検収の前の受注は「検収済」にならない。同じ検収完了を 2 回流しても `inspection_records` が増えない（冪等の共有テスト）
- 結合（`spec/requests/inspections_spec.rb`）：`inspectInboundShipment` → イベントを流す → 受注が「検収済」

**実装する文書の節**：`context-map.md`「検収と請求の流れ」1・2、`data-model.md`「購買（`purchasing`）」「受注（`sales`）」の検収の表

**文書に残すこと**：検収の入力の規則を `context-map.md`「検収と請求の流れ」に書く。

## M24 請求の締め

**目的**：締めは取引先ごとに直列になる。消費税は請求書・税率ごとに 1 回だけ切り捨てる。前の期間の遅れた検収も次の締めで拾う。

**作るもの**：請求対象確定のイベントと配送表の行、受注の検収完了の受け手（M23）からの請求対象確定の発行、`billing_terms`・`billable_items`・`invoices`・`invoice_tax_summaries`、請求対象確定の受け手 `Billing::SalesEventReceiver`、`Billing::Terms`・`Billing::BillableItems`・`Billing::Closing.close`・`discard`、`supplier.billingTerms`・`supplier.billableItems`・`supplier.invoices`・`supplier.invoice`、`setBillingTerm`・`closeBillingPeriod`・`discardDraftInvoice`（どれも `audit_exempt`）

締めの入力と結果は次のとおりである。

| 入力・状態 | 結果 |
|---|---|
| 取引先が、自社が受注側の取引関係（失効したものを含む）の相手でない | `NOT_FOUND`（`path` は取引先）。`setBillingTerm`・`supplier.billableItems` も同じ。S1 の表に行を足す |
| 取引先に請求条件が無い | `NOT_FOUND`（`path` は取引先） |
| `setBillingTerm` の締め日が 1〜28・31 の外 | `INVALID_INPUT` |
| 締め日が請求条件の締め日（31 は月末）に当たらない | `INVALID_INPUT` |
| 取引先に下書きの請求書がある | `CONFLICT` |
| 締め日が、同じ取引先の前の請求書（下書きを除く）の `period_end` 以前 | `INVALID_INPUT`。期間が逆転するか重なるからである |
| 締め日以前に検収された未請求明細が 0 件 | `CONFLICT`。請求書を作らない |
| それ以外 | 締め日以前に検収された未請求明細をすべて集めて下書きを作る |
| 発行済みの請求書を破棄する | `CONFLICT` |

請求番号は、下書きでは振らず、確定（M25 の `issue`）で振る。破棄した下書きで欠番を作らないためである。採番の表（`invoice_sequences`）は M25 で足し、M24 の下書きは `invoice_number` を空にする。そのため `Invoice.invoiceNumber` は null を許す型（`String`）にする（`graphql-schema.md`）。

請求書の期間は、`period_end` を指定した締め日、`period_start` を同じ取引先の前の請求書（下書きを除く）の `period_end` の翌日にする。前の請求書が無ければ、集めた明細の最も古い検収日にする。遅れて届いた前の期間の検収は、検収日が `period_start` より前でも集める。期間は請求書の表示のためのもので、集める明細は検収日が締め日以前かどうかだけで決まる。

**完了条件**

```sh
bundle exec rspec packs/billing/spec/public/billing/closing_spec.rb packs/billing/spec/public/billing/sales_event_receiver_spec.rb \
  packs/sales/spec/public/sales/purchasing_event_receiver_spec.rb spec/requests/inspections_spec.rb spec/requests/billing_spec.rb
bundle exec rspec packs/billing/spec/concurrency/billing/closing_lock_spec.rb
```

- 単体（`closing_spec.rb`）：上の表の各行。税率 8% と 10% が混ざる明細で、税額が明細ごとの丸めの合計と異なる例。末日締め（31）を 2 月と 30 日の月で。締めの後に届いた前の期間の検収が次の締めで集まり、締め日より後の検収が集まらない。前の請求書の `period_end` と同じ締め日を拒む。下書きの破棄で明細が未請求に戻る
- 単体（`sales_event_receiver_spec.rb`）：同じ請求対象確定を 2 回流しても明細が 1 件（冪等の共有テスト）
- 単体（`purchasing_event_receiver_spec.rb` に足す）：検収完了の受け手が、検収した受注明細ごとに請求対象確定を出す
- 結合（`spec/requests/inspections_spec.rb` に足す）：検収 → イベントを流す → 受注側に未請求の請求対象明細ができる。`spec/requests/billing_spec.rb`：`closeBillingPeriod` と `discardDraftInvoice` の成功と失敗の写し。`invoiceNumber` を選んだ `supplier.invoice` と `supplier.invoices` が、下書きでもエラーにならず空を返す
- 競合（`closing_lock_spec.rb`）：同じ取引先の締めを 2 つの接続で同時に走らせ、下書きが 1 件だけでき、もう一方が `CONFLICT` になる。請求条件の行ロックで待つことを確かめる

**実装する文書の節**：`data-model.md`「請求（`billing`）」、`context-map.md`「検収と請求の流れ」3〜5 と請求書の組み立ての規則

**文書に残すこと**：締めの入力と結果の表と、請求書の期間の決め方と、請求番号を確定で振ることを `data-model.md`「請求（`billing`）」に書く。

## M25 請求書の発行と受領請求書

**目的**：確定した請求書と明細は変わらない。写しは発注側の名義で 1 回だけ作られる。

**作るもの**：`Billing::Closing.issue`（確定で請求番号を振る。採番の表 `invoice_sequences` を足す。M24 で決めた）、請求書発行のイベント、購買の受け手（`received_invoices`・明細）、`Purchasing::ReceivedInvoices`、`issueInvoice`、`buyer.receivedInvoices`・`buyer.receivedInvoice`

**完了条件**：確定で請求番号が振られ、確定した請求書の `invoiceNumber` が空でないテスト。確定後の変更が拒否されるテスト。同じ請求書発行を 2 回流しても写しが 1 件のテスト。`total = subtotal + tax_total` の CHECK 制約のテスト。重要シナリオ S5（`spec/scenarios/billing_amounts_spec.rb`）が通る。

**実装する文書の節**：`context-map.md`「検収と請求の流れ」5・6、`data-model.md`「購買（`purchasing`）」の受領請求書

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

- パッケージ `packs/notifications`（`Notifications::`）。依存先は `platform`・`partnerships`（宛先のメールアドレスを自社の `users` から引く）。`sales`・`purchasing` の依存先に `notifications` を足す。`context-map.md`「疎結合を守る規則」の依存の向きの表に `notifications` の行（`platform`・`partnerships`）を足し、`sales`・`purchasing` の行の依存先に `notifications` を足す。表は `email_deliveries` と `webhook_inbox_events`（`data-model.md`「通知（`notifications`）」）。
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

- パッケージ `packs/imports`（`Imports::`）。依存先は `platform`・`partnerships`・`sales`・`inventory`。`context-map.md`「疎結合を守る規則」の依存の向きの表に、この行を足す。表は `imports`・`import_files`・`import_rows`（`data-model.md`「取り込み（`imports`）」）。
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
- コードのコメント：写す担当者は、流用元の仕様・タスク・台帳の番号を指すコメント（`T-34`・`仕様 §7`・`正本 N-5`・流用元の台帳の `OI-NN` の類）を、いまの振る舞いと理由に書き直すか消す。`guides/comments.md` の対象に `frontend/` を足し、`frontend/scripts/check-comments.mjs` が、これらの番号とマイルストーンの番号を含むコメントを落とす。`npm run lint` から呼ぶ。

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
