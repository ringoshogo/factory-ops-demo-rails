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

M2 以降のすべてのマイルストーンで、実装者は PR を出す前に次のコマンドを流し、成功させる。CI（M1 で作る）も同じ検査を流す。検査を足したマイルストーンより後では、その検査も共通の完了条件に加わる。`bin/ci` は、`--due` のほかのこれらを CI と同じ形で 1 つで流す。

```sh
bin/rubocop                                   # M15 からコメントの規約の Cop を含む
bin/packwerk validate && bin/packwerk check   # M2 から
bin/brakeman --no-pager                       # Rails のコードの静的なセキュリティ検査
bin/bundler-audit                             # gem の既知の脆弱性
bin/rails db:test:prepare
COVERAGE=1 bundle exec rspec --format progress --format json --out tmp/rspec.json
BASE_REF=origin/<向き先のブランチ> bin/check-branch-coverage   # M35 から。どの example も通らない分岐の一覧（失敗にはしない）
bin/test-layers tmp/rspec.json                # M16 から。テストの層ごとの件数の報告
bin/check-structure                           # structure.sql の往復の検査
bin/check-schema-compat                       # M20 から。GraphQL のスキーマの破壊的変更の検査
bin/check-alerts                              # M31 から。警報の規則の式と、テストの系列での発火と不発火
bin/check-open-items --due M<番号>            # 引当先がこのマイルストーンの残件が、open と blocked-user のまま残っていない
bin/check-commit-refs                         # 台帳・証跡・引き継ぎに書いた SHA が HEAD の祖先である
```

この一覧は、CI のワークフローが流す `bin/` の検査をすべて含む。`spec/platform/ci_checks_spec.rb` が、ワークフローの `bin/` のコマンドがこの一覧と `config/ci.rb` の工程にあることを確かめる。一覧に無い検査は、PR を出してから CI で初めて落ちる。

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

残りの業務機能（M21〜M26）の前に、横断の仕組み（M15〜M20）を入れる。横断の仕組みは、mutation の宣言・イベントの引数・テストの置き場・CI の検査を変える。業務機能の後に入れると、M21〜M26 で書いた mutation・イベント・テストを書き直すことになる。業務機能を終えた後に、見せどころ（M27〜M31）を足す。最後に、シード（M32）と、それを使って E2E を流すフロントエンド（M33）を作り、公開の配置（M41）で終える。フロントエンドの前に、画面が一覧を 1 ページずつ読むための API（M39・M40）を足す。

M34・M35 は、サイクル 01 の改善の探索（`plans/cycle-01/improvement.md`）で採用した変更である。M21 より前に実装する（`guides/dev-cycle.md`「全体の流れ」）。M21 以降の番号を振り直すと、台帳・証跡・文書の参照が崩れるので、番号は末尾に足し、節は実装の順に M20 の後へ置く。M36 は、サイクル 02 の改善の探索（`plans/cycle-02/improvement.md`）で採用した変更で、同じ理由で節を M24 の後に置き、M25 より前に実装する。M37 は、サイクル 03 の改善の探索（`plans/cycle-03/improvement.md`）で採用した変更で、節を M29 の後に置き、M30 より前に実装する。M38 は、サイクル 04 の改善の探索（`plans/cycle-04/improvement.md`）で採用した変更で、節を M32 の後に置き、M33 より前に実装する。M39〜M41 は、作者が M33 の著者判断で一覧の読み方と公開の配置を変えた（OI-07・OI-14）ので、M33 から分けたマイルストーンである。M39・M40 は節を M38 の後に置いて M33 より前に、M41 は節を M33 の後に置いて M33 の後に実装する。

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
| M12 | 在庫と引当 | 有効在庫が負にならず、在庫の数量の変更が必ず移動履歴を残す |
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
| M36 | 行列テストの世界の作り方と、テストの検出力の小さな穴 | 行列テストの時間が表の数に比例し、競合テストの後始末の呼び忘れが落ちる |
| M25 | 請求書の発行と受領請求書 | 確定した請求書が変わらず、写しが発注側に 1 回だけ届く。`admin` に限る操作を `member` が呼ぶと `FORBIDDEN` になる |
| M26 | ダッシュボードと失効の通し試験 | 失効の後も連結済みの取引が請求まで進む |
| M27 | 販売単価のバイテンポラル履歴 | 現在の単価の有効期間が重ならず、単価の行が書き換わらない |
| M28 | 外部サービスの呼び出しと非同期の型 | 外部への作用が 1 つの登録口からだけ登録され、テストと開発で本物の SendGrid を呼べない |
| M29 | 大量データの取り込み | 取り込みが他のキューを待たせず、中断しても続きから再開し、他社の名義で書けない |
| M37 | RLS が隠す scope の抜けと、読み取りの役割を行列で捕まえる | 入口の scope を外すと、RLS が同じ行を隠していても行列が落ちる。`admin` に限る読み取りを `member` で呼ぶと行列が確かめる |
| M30 | メトリクス | メトリクスのラベルにテナントとユーザーが入らない |
| M31 | SLO と障害対応の手順書 | どの警報も手順書を持ち、警報の規則が CI で検査される |
| M32 | シードデータ | シードと E2E の世界が 1 つの作り方から、公開 API とイベントだけで作られ、`admin` に限る段は mutation と同じ規則を通る。業務の日付が日本時間の今日で決まり、システムの時刻帯で決まる呼び出しを Cop が落とす。操作者のいない入口の公開 API が所有の条件を明示し、RLS を開いても他社の行を数えない |
| M38 | RLS の UPDATE のポリシーが隠す所有の条件を、単体で捕まえる | 操作者のいない入口の公開 API とイベントの受け手から所有の条件を外すと、RLS の UPDATE のポリシーが同じ行を隠していても単体が落ちる |
| M39 | 一覧の件数と並べ替え、列での絞り込み | 一覧の件数と並びが、ページと同じ scope と絞り込みで決まり、RLS を開いた比較で件数と並びの scope の抜けが落ちる |
| M40 | 状況での絞り込み | 状況を 1 つの SQL の式で導出し、一覧の表示・絞り込み・件数とダッシュボードの件数が同じ式を読む |
| M33 | フロントエンド | 画面の問い合わせが `schema.graphql` で型検査され、同じ種類の要素の寸法とそろえが全画面で測られる |
| M41 | Raspberry Pi の k3s への配置 | マニフェストが Secret を持たず、所有ロールの資格情報とデモの世界の許可が、作り直しとマイグレーションの工程にだけ渡る |

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
| M36 | M24 | 行列テストの世界に、M24 までの表と入口がそろっている |
| M25 | M36 | 行列テストの役割の列を、M36 で作り直した世界に足す |
| M21〜M26 | M15〜M20・M34・M35 | 新しい mutation に監査の宣言を、イベントに付帯情報を、テストに層を、型の変更に `schema.graphql` の書き直しを伴わせる。上げた Ruby で書き、足した分岐の未通過を警告で見る |
| M27 | M19・M20・M25 | 単価の変更を監査する。請求書の説明が発行済みの請求書を使う |
| M28 | M18・M25 | 送信の失敗をログに出す。確実な通知の呼び出し元が「請求書発行」の受け手である |
| M29 | M27・M18 | 単価の列を `Sales::ItemPrices` で反映する。進み具合をログに出す |
| M37 | M29 | 入口の行列に、M29 までの入口と `admin` に限る操作がそろっている |
| M30 | M18・M28・M29 | 値の出どころが M18 の構造化イベントで、外部の呼び出しと取り込みの値も測る |
| M31 | M30 | SLO と警報を M30 のメトリクスで書く |
| M32 | M31 まで | シードが単価の履歴と取り込みも含む |
| M38 | M32 | 操作者のいない入口の規則と、M38 が UPDATE にも広げる共有の文脈が M32 にある |
| M39 | M37・M38 | 一覧の件数と絞り込みの scope の抜けを、M37 の RLS を開いた 2 回目の比較で捕まえる。行列の補助と共有の文脈を M38 が変えた後に、行列の行を足す |
| M40 | M39 | 状況の絞り込みを、M39 の入力型・件数・ページの土台に足す |
| M33 | M32・M40 | 画面が呼ぶ入口が M29 までに、一覧の並べ替え・絞り込み・件数が M40 までにそろい、E2E の世界を M32 の `DemoWorld` で作る |
| M41 | M33 | 画面のイメージを `frontend/` から作り、作り直しで M32 の `DemoWorld` を流す |

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

**目的**：有効在庫は負にならない。在庫の数量の変更は必ず 1 つの内部メソッドを通り、移動履歴を残す。全量を引き当てた受注だけが出荷可能になる。

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
- 画面の問い合わせの一覧（`frontend/graphql/<視点>/<操作名>.graphql`。M33 で `spec/fixtures/graphql/screens/` から移し、画面が実際に送る文書を正本にした）：画面が送る問い合わせを、操作名を付けて 1 ファイル 1 つで置く。M17 では、M33 の画面の一覧のうち M14 までの入口で動く画面について、次の表の問い合わせを作る。後のマイルストーンは、入口を足すたびに、それを使う画面の問い合わせをここへ足す。一覧には mutation の文書も入るので、クエリ数の予算と M26 の複雑度のテストは query の文書だけを読み、M30 の操作名の登録は query と mutation の両方を照らす。

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

- 計測：`spec/spec_helper.rb` は、環境変数 `COVERAGE=1` のときだけ、ファイルの先頭（Rails とアプリを読み込む前）で標準の `Coverage` を分岐で始め、rspec の終わりに結果を `tmp/coverage.json` に書く。gem は足さない。結果は、計測の対象のファイルごとに、分岐の座標（種類・開始の行と列・終わりの行と列・条件の始まる行）と通過の回数の組を配列で持つ
- 計測の範囲：計測の対象は、rspec のプロセスが読み込んだ `app/`・`packs/*/app/`・`packs/*/lib/`・`lib/` の Ruby のファイルである。子のプロセス（`spec/platform/logging_spec.rb` の本番の起動、`spec/bin` が流す `bin/` のスクリプト）は測らない。`bin/` のスクリプトと `config/`・`db/` は対象の外にする
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
- イベントの届く順の入れ替わり（OI-65）：出荷停止解除が出荷停止より先に、出荷取消が出荷可能より先に動いても、停止や出荷依頼が取り残されない受け手にする。決め方は `data-model.md`「イベントの届く順の入れ替わり」に書いた。イベントの値だけで終わった状態の行を作れるなら先に作り（出荷停止解除・出荷取消が出荷停止より先に届いたら、解除済みの出荷停止を作る）、作れないなら例外で失敗させて再配送に任せる（出荷取消が出荷可能より先に届いたとき）。そのため出荷取消は、承認した審査 ID と、出荷可能を出したかを運ぶ
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

**目的**：受注側は審査なしで取り消せる。同時に進んだ取消と出荷計上は、在庫の行 → 引当の行の順に取る行ロックでどちらか一方だけが成立する。

**作るもの**：`Sales::OrderCancellation.cancel`（M21 の受注の内部の取消の処理を使う）、受注取消のイベントと購買の受け手（`supplier_cancelled_at`）、`cancelSalesOrder`（`audit`。action・対象・相手の行を `graphql-schema.md`「監査ログ」の表に足す）。出荷取消のイベントと出荷の受け手は M21 のものを使う。審査の承認（M21）と受注側の取消は同じ受注の内部の取消の処理を通るので、下の競合テストが両方の経路の在庫の行と引当の行のロックを確かめる。

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

**作るもの**：`receipt_inspections`・明細、`inspection_records`、`Purchasing::ReceiptInspections.record`、検収完了のイベントと配送表の行、検収完了の受け手（M21 の `Sales::PurchasingEventReceiver` に足す）、受注の「検収済」と発注の「検収済」、`inspectInboundShipment`（`audit`。action・対象・相手の行を `graphql-schema.md`「監査ログ」の表に足す）、`InboundShipment.inspection`・`InboundShipmentLine.acceptedQuantity`

請求対象確定のイベントは M23 では足さない。受け手（M24）の無いイベントを配送表に載せると、配送表の spec（`spec/contracts/subscriptions_spec.rb`）が受け手の無い行で落ち、載せないと `Contracts.publish` が配送表に無いイベントで失敗するからである。イベント・配送表の行・受注の受け手からの発行・請求の受け手は、M24 で同時に足す。

検収の入力と結果は次のとおりである。入力の誤りは `INVALID_INPUT` で、`path` に誤りの明細を示す。

- 入荷の全明細を 1 回で出す。明細の省略、同じ明細の重複、別の入荷の明細は入力の誤りにする
- 検収数量は 0 以上・出荷数量以下の整数にする。0 は全量の不合格を表す
- 同じ入荷への 2 回目の検収は、入力を確かめる前に `CONFLICT` にし、検収完了を出さない
- 検収日は、検収を登録した日（自社の日付）にする

**完了条件**

```sh
bundle exec rspec packs/purchasing/spec/public/purchasing/receipt_inspections_spec.rb \
  packs/sales/spec/public/sales/purchasing_event_receiver_spec.rb spec/requests/inspections_spec.rb
```

- 単体（`receipt_inspections_spec.rb`）：上の入力の各誤り。出荷数量を超える検収が `INVALID_INPUT` になる。2 回目の検収が `CONFLICT` で、検収完了のジョブが 1 件のままである。検収の後に発注が「検収済」になる
- 単体（`purchasing_event_receiver_spec.rb`）：検収完了で受注が「検収済」になる（分納しないので、出荷実績は受注ごとに 1 件で、1 回目の検収完了がすべての出荷実績の検収になる）。検収の前の受注は「検収済」にならない。同じ検収完了を 2 回流しても `inspection_records` が増えない（冪等の共有テスト）
- 結合（`spec/requests/inspections_spec.rb`）：`inspectInboundShipment` → イベントを流す → 受注が「検収済」

**実装する文書の節**：`context-map.md`「検収と請求の流れ」1・2、`data-model.md`「購買（`purchasing`）」「受注（`sales`）」の検収の表

**文書に残すこと**：検収の入力の規則を `context-map.md`「検収と請求の流れ」に書く。

## M24 請求の締め

**目的**：締めは取引先ごとに直列になる。消費税は請求書・税率ごとに 1 回だけ切り捨てる。前の期間の遅れた検収も次の締めで拾う。

**作るもの**：請求対象確定のイベントと配送表の行、受注の検収完了の受け手（M23）からの請求対象確定の発行、`billing_terms`・`billable_items`・`invoices`・`invoice_tax_summaries`、請求対象確定の受け手 `Billing::SalesEventReceiver`、`Billing::Terms`・`Billing::BillableItems`・`Billing::Closing.close`・`discard`、`supplier.billingTerms`・`supplier.billableItems`・`supplier.invoices`・`supplier.invoice`、`setBillingTerm`・`closeBillingPeriod`・`discardDraftInvoice`（どれも `audit_exempt`）

締めの入力と結果は次のとおりである。締めは、`setBillingTerm` の行を除いて上から順に確かめ、最初に当たった結果を返す。

| 入力・状態 | 結果 |
|---|---|
| 取引先が、自社が受注側の取引関係（失効したものを含む）の相手でない | `NOT_FOUND`（`path` は取引先）。`setBillingTerm` も同じ。`supplier.billableItems` は、取引先でないテナントで絞ると空になる。S1 の表に行を足す |
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
- 単体（`purchasing_event_receiver_spec.rb` に足す）：検収完了の受け手が、検収数量が正の受注明細ごとに請求対象確定を出す。数量 0 の明細には出さない
- 結合（`spec/requests/inspections_spec.rb` に足す）：検収 → イベントを流す → 受注側に未請求の請求対象明細ができる。`spec/requests/billing_spec.rb`：`closeBillingPeriod` と `discardDraftInvoice` の成功と失敗の写し。`invoiceNumber` を選んだ `supplier.invoice` と `supplier.invoices` が、下書きでもエラーにならず空を返す
- 競合（`closing_lock_spec.rb`）：同じ取引先の締めを 2 つの接続で同時に走らせ、下書きが 1 件だけでき、もう一方が `CONFLICT` になる。請求条件の行ロックで待つことを確かめる

**実装する文書の節**：`data-model.md`「請求（`billing`）」、`context-map.md`「検収と請求の流れ」3〜5 と請求書の組み立ての規則

**文書に残すこと**：締めの入力と結果の表と、請求書の期間の決め方と、請求番号を確定で振ることを `data-model.md`「請求（`billing`）」に書く。

## M36 行列テストの世界の作り方と、テストの検出力の小さな穴

**目的**：表と入口を足すたびに 2 乗で伸びる行列テストの時間を、守る性質を弱めずに表の数に比例する時間へ戻す。あわせて、サイクル 02 の改善の探索で採用した 3 つの小さな穴（競合テストの後始末の呼び忘れ、request spec の補助の複製、上限ちょうどの example）を閉じる。どれも業務の振る舞いを変えない。

**作るもの**

1. 行列テストの世界をファイルごとに 1 回作る（IB-27）：`spec/matrix/table_matrix_spec.rb` と `spec/matrix/graphql_matrix_spec.rb` の `let(:world) { MatrixWorld.new }` を、`before(:context)` で接続を固定（`ActiveRecord::ConnectionPool#pin_connection!`）して外側のトランザクションの中で世界を作り、`after(:context)` で巻き戻して固定を外す形にする。準備か example が失敗しても、外側のトランザクションと接続の固定を必ず外す。各 example は、いまと同じく rspec-rails の savepoint の中で動いて巻き戻る。`after(:context)` で `unpin_connection!` が偽を返したら（世界のトランザクションが途中でコミットされたか、外で巻き戻った）失敗させる。行列の spec が別の接続を使わないことは `guides/testing.md` の規則で守る（OI-87）。`pin_connection!` は Rails の公開の文書に無いメソッドなので、依存していることと、使えなくなったときの移り先（判断の裏返る条件）を `guides/testing.md` に書く。世界のオブジェクト（関連を読み込んだ AR のインスタンス）を example の間で使い回すので、example が世界のオブジェクトを書き換えないことと、テナントの設定（`Tenancy`）が example の外へ漏れないことを確かめる。補助のガードの example は `spec/matrix/matrix_world_spec.rb` に置く
2. 競合テストの後始末の呼び忘れを落とすガード（IB-26、ガードの example は `spec/concurrency/cleanup_guard_spec.rb`）：`delete_owned_rows` が正常に終わった後に印を立て、印は example ごとに下ろす（印を example のインスタンスに持たせ、rspec が example ごとにインスタンスを作り直すことで下ろす）。設定の `config.after(:example)` で、`:concurrency` の example に印が無ければ失敗させる。後始末を外した競合テストがコミットしたイベントのジョブは、テナントで絞らない `deliver_enqueued_events` に後の example で拾われるので、呼び忘れは離れた example の失敗になる。`:concurrency` の外でトランザクションを使わない spec（`packs/sales/spec/public/sales/sales_order_policy_spec.rb`・`spec/db/tenant_table_spec.rb`・`spec/platform/tenancy_session_spec.rb`）は自前で後始末するので、ガードの外にあることを補助のコメントに列挙する。ガードは、渡すテナントの漏れ（factory が暗に作ったテナント）は捕まえない。`spec/concurrency/concurrency_helpers_spec.rb` は本文で `delete_owned_rows` を呼ぶので、印は `after` があることそのものではなく、後始末が終わったことを示す
3. request spec の補助を `spec/support/request_helpers.rb` に寄せる（IB-09）：`login_as(user)` と、応答をそのまま返す `graphql_body` を置き、`type: :request` と `ScenarioHelpers` に取り込む。トップレベルのエラーが無いことを確かめて `data` を返す形は、`ScenarioHelpers#query` を同じモジュールへ移して使う。`type: :request` の行列と Bullet の spec で名前がぶつからないことを確かめる。`spec/requests/supplier_shipments_spec.rb` の確かめてから本文を返す形と、`graphql_entry_spec.rb` のメールを取る `login_as` は残す。`mutate` は寄せない
4. 上限ちょうどの example（IB-25）：検収の明細の件数（異なる有効な明細 100 件で成功する）と、在庫の調整の理由の長さ（200 文字で成功し、201 文字で `INVALID_INPUT` になり書き込みが無い）の example を足す。在庫の調整には単体の spec が無いので、`packs/inventory/spec/public/inventory/adjustment_spec.rb` を足す。入力は定数から作らず、仕様の値（100・200）で書く。検収の上限の定数は発注の定数の別名なので、検収の example は比較の `>` を `>=` に壊すと落ちることで確かめる。上限 + 1 と上限ちょうどの両方を仕様の値で書く規則は、規則の変更として M29（取り込みのファイルの大きさの上限）で試し（IB-25 は `試行中`）、効いたら `guides/testing.md`「層への配分」に書く

実装者は、作るもの 1 を最初に行う。変える前の形と、RLS を外したときに落ちる集合を比べるためである。3 は機械的な置き換えなので最後にし、差分を分ける。

**判断**：世界をファイルごとに作るのに gem（test-prof の `before_all`）を使うか

- **既定の推奨**：使わない。test-prof の `before_all` も同じ `pin_connection!` を包んだもので、要るのは 2 ファイルの外側のトランザクションと接続の固定だけである
- **裏返る条件**：同じ形を 3 つ以上のファイルで使うことになった → test-prof の `before_all` に移す。`pin_connection!` が Rails の更新で使えなくなった → test-prof の `before_all` がその版で何を使っているかを確かめて移るか、`let(:world)` に戻す。`before_all` も同じ `pin_connection!` を包んでいるので、移るだけでは退路にならない（IB-28）
- **撤退コスト**：小さい。`let(:world)` に戻すだけで済む

**完了条件**

```sh
bundle exec rspec spec/matrix                       # 0 failures。行列の 2 ファイルが合計 30 秒以下（手元）
for seed in 1 2 3; do bundle exec rspec spec/matrix --order rand --seed $seed || exit 1; done
bundle exec rspec spec/concurrency/concurrency_helpers_spec.rb spec/concurrency/cleanup_guard_spec.rb spec/requests spec/scenarios
bundle exec rspec packs/purchasing/spec/public/purchasing/receipt_inspections_spec.rb packs/inventory/spec/public/inventory/adjustment_spec.rb   # 在庫の調整の単体の spec は、このマイルストーンで足す
test "$(grep -rh "def login_as(user)" spec | wc -l)" -eq 1   # spec/support/request_helpers.rb の 1 か所。git に登録する前でも数える
```

- 行列：テナントの表 1 つの RLS を外すと、表の行列で変える前と同じ example の集合が落ちる。入口の行列でも、認可の確かめを 1 つ外すと、変える前と同じ集合が落ちる。example の中で行を足しても、次の example とファイルの終わりの後に残らない
- 後始末のガード（`cleanup_guard_spec.rb`）：`after` を持たない競合テストの内側の example が落ちる（`spec/platform/bullet_spec.rb` の内側の example group を走らせる型）。ガードを外すと、その example が落ちなくなる
- 補助：寄せる前と後で、各 request spec の返り値とエラーの確かめ方が同じである
- 上限：上限の定数を 1 つ下げると、上限ちょうどの example が落ちる
- CI の test のジョブの Run tests を PR の CI で 3 回以上流し、中央値が 4 分以下であることを記録する。あわせて、全件の分岐の計測ありとなしの時間を 1 回ずつ測って証跡に書く（IB-01 の費用の確かめ）

**実装する文書の節**：`guides/testing.md`「行列テストとの分担」「競合テスト」「層への配分」

**文書に残すこと**：行列テストの世界をファイルごとに作ることと、行列の spec では別の接続を使わず世界のオブジェクトを書き換えないことを `guides/testing.md`「行列テストとの分担」に書く。後始末のガードを「競合テスト」の 5 に書く。

## M25 請求書の発行と受領請求書

**目的**：確定した請求書と明細は変わらない。写しは発注側の名義で 1 回だけ作られる。取引を取り消す操作と、検収と請求で金額を確定させる操作は、`admin` だけが行える（`context-map.md`「自社の中の役割」）。

**作るもの**

1. 確定と写し：`Billing::Closing.issue`（確定で請求番号を振る。採番の表 `invoice_sequences` を足す。M24 で決めた。入力と結果、ロック、確定した請求書を変えないトリガーは `data-model.md`「請求（`billing`）」。OI-84）、請求書発行のイベントと配送表の行、購買の受け手 `Purchasing::BillingEventReceiver`（`received_invoices`・明細）、`Purchasing::ReceivedInvoices`、`issueInvoice`、`buyer.receivedInvoices`・`buyer.receivedInvoice`。`issueInvoice` の規則は `Billing::InvoicePolicy#issue?` で、`admin` に限る。`issueInvoice` は `audit` で、監査の行は `graphql-schema.md`「監査ログ」の表にある。`received_invoices`・`received_invoice_lines`・`invoice_sequences` の表の行列の行と、S1 の表に `issueInvoice(input.invoiceId)`・`buyer.receivedInvoice(id)` の行を足す。購買は「請求書発行」をイベントの契約だけで受けるので、パッケージの依存は変わらない
2. 締め日（OI-77）：締め日が今日より後の締めを許し、確定も締め日を過ぎるのを待たずにできる（`data-model.md`「請求（`billing`）」）。締めの後に届いた、検収日が締め日以前の検収は、次の締めで集まる
3. 役割による制限（OI-71〜OI-73）：サイクル 02 で作った mutation の規則のうち、`graphql-schema.md`「役割による制限」の表で `admin` に限るものを、`user.admin?` を条件に含める形に直す。対象は `Sales::SalesOrderPolicy#review?`・`#cancel?`、`Purchasing::PurchaseOrderPolicy#request_cancellation?`・`#inspect_receipt?`、`Billing::InvoicePolicy#set_term?`・`#close?`・`#discard?` の 7 つで、いまはどれも役割を問わない。`member` で `admin` に限る操作を呼んでいる既存の request spec（`spec/requests/inspections_spec.rb`・`spec/requests/billing_spec.rb`・`spec/requests/cancellations_spec.rb`）は、`admin` で呼ぶ形に直す
4. 行列テストの役割の列：`MatrixWorld` が、各ペルソナのテナントに `admin` に加えて `member` のユーザーを作る。`spec/matrix/graphql_expectations.rb` の mutation の行は、許す役割（`admin` か `member`）を必ず持つ。`graphql_matrix_spec.rb` は、`admin` の行を、値を返すペルソナの `member` でも呼び、`FORBIDDEN` になって何も書かれないこと（呼ぶ前と後で、そのペルソナのテナントの表ごとの行の数と中身が、監査の行を含めて変わらないこと。既存の行を書き換えるだけの mutation は行の数を変えないので、中身も比べる）を確かめる。`member` の行は、どのペルソナの `member` で呼んでも `admin` と同じ結果になり、値を返さないときは何も書かれないことを確かめる（OI-90・OI-107）。役割を持たない mutation の行があれば落ちる

役割による制限をここに置くのは、確定（`issueInvoice`）で同じ形の規則を初めから作るからである。サイクル 03 は 6 つのマイルストーンで上限に達しているので、新しいマイルストーンは作らない。M36 は業務の振る舞いを変えないマイルストーンなので入れず、行列テストの役割の列は、M36 で作り直した世界に足す。

**完了条件**

```sh
bundle exec rspec packs/billing/spec/public/billing/closing_spec.rb packs/purchasing/spec/public/purchasing/billing_event_receiver_spec.rb \
  packs/purchasing/spec/public/purchasing/received_invoices_spec.rb packs/sales/spec/public/sales/sales_order_policy_spec.rb \
  packs/purchasing/spec/public/purchasing/purchase_order_policy_spec.rb packs/billing/spec/public/billing/invoice_policy_spec.rb \
  spec/requests/billing_spec.rb spec/requests/inspections_spec.rb spec/requests/cancellations_spec.rb \
  spec/scenarios/billing_amounts_spec.rb spec/scenarios/tenant_boundary_spec.rb
bundle exec rspec packs/billing/spec/concurrency/billing/closing_lock_spec.rb packs/purchasing/spec/concurrency/purchasing/billing_event_receiver_lock_spec.rb
bundle exec rspec spec/matrix spec/graphql/authorization_declarations_spec.rb spec/db
```

- 単体（`closing_spec.rb`）：確定で請求番号が振られ、確定した請求書の `invoiceNumber` が空でない。確定の表の各行（他社の請求書・存在しない ID は `NOT_FOUND`、2 回目の確定は `CONFLICT`）。今日より後の締め日で締めて確定でき、その後に届いた締め日以前の検収が次の締めで集まる
- 単体（`billing_event_receiver_spec.rb`）：同じ請求書発行を 2 回流しても写しが 1 件（冪等の共有テスト）
- 単体（policy の spec）：役割を直した 7 つと `issue?` の規則が、`admin` には真、`member` には偽を返す。`purchase_order_policy_spec.rb` と `invoice_policy_spec.rb` は、このマイルストーンで足す
- 競合（`closing_lock_spec.rb` に足す）：確定と破棄、確定と確定を 2 つの接続で同時に走らせ、どちらか一方だけが成り立つ。請求条件の行ロックで待つことを確かめる。確定が開いている間の同じ取引先の締めも、請求条件の行ロックで待つ。公開 API を通らない明細の書き換えと確定が並んだときも、トリガーが請求書の行の共有ロックで待ち、確定の後なら拒む。同じ「請求書発行」の 2 つの配送が同時に届いても、受領請求書は 1 件になる（`packs/purchasing/spec/concurrency/purchasing/billing_event_receiver_lock_spec.rb`）
- DB（`spec/db`）：`received_invoices` の `total = subtotal + tax_total` の CHECK 制約が、外れた行を拒む。確定した請求書の UPDATE と DELETE、それに結んだ集計と明細の INSERT・UPDATE・DELETE、未請求の明細を確定した請求書へ結び付ける UPDATE を、トリガーが拒む（SQL で直接書いて確かめ、明細の集まりと集計が変わらない）
- 行列（`graphql_matrix_spec.rb`）：上の作るもの 4。`admin` に限る規則の 1 つから `user.admin?` を外すと、その mutation の `member` の行が落ちる
- シナリオ（`spec/scenarios/billing_amounts_spec.rb`、重要シナリオ S5）が通る

**実装する文書の節**：`context-map.md`「検収と請求の流れ」5・6・「自社の中の役割」、`data-model.md`「請求（`billing`）」「購買（`purchasing`）」の受領請求書、`graphql-schema.md`「役割による制限」「監査ログ」

**文書に残すこと**：行列の時間（M36 の完了条件と同じコマンド）を、役割の列を足した後に測り、実装レビューの節に書く。

## M26 ダッシュボードと失効の通し試験

**目的**：取引関係を失効させると 3 つの読む経路と新しい発注が閉じ、連結済みの取引はイベントで請求まで進む。この見せどころを 1 本のテストで示す。受注側は、受注の状況・安全在庫・出荷期限・未請求の額を 1 つの画面の問い合わせで見られる。

**作るもの**

1. `supplier.dashboard` と型 `SupplierDashboard`・`SalesOrderStatusCount`（`graphql-schema.md`「読み取りの一覧」の 4 つの公開 API と集計の境界）。画面の問い合わせ `supplier_dashboard.graphql`（M33 で `frontend/graphql/supplier/SupplierDashboard.graphql` に移した）を足し、クエリ数の予算の表と行列テストの期待値（`SupplierView.dashboard`）に行を足す
2. `spec/scenarios/revocation_spec.rb`（重要シナリオ S2）：発注 → 受注確定 → 失効 → 経路 1〜3 が空・新しい発注が `NOT_PERMITTED` → 引当・出荷・検収・締め・発行がそのまま進み、発注側に受領請求書が届く
3. 画面の問い合わせごとの複雑度のテスト `spec/graphql/query_complexity_spec.rb`（`graphql-schema.md`「ページングと N+1」）。問い合わせは、M17 の画面の問い合わせの一覧（M33 で `frontend/graphql/` に移し、query の文書だけを読む）から読み、どのファイルも `max_complexity` に収まることを確かめる。一覧に無いファイルが無いことも確かめる
4. 出荷依頼がまだ無い受注への「出荷停止」の受け手と、出荷可能の受け手・出荷指示の作成の競合（OI-79）。競合テストは、停止の受け手を、出荷依頼の無いことを読んだ後・コミットの前で止めておき（`hold_open`）、その間に出荷可能の受け手と出荷指示の作成を通す、決まった順で書く。ロックの無い経路なので、ただ同時に流すと起きるかどうかが毎回変わる。停止中の受注に有効な出荷指示が残るなら、停止の受け手と出荷可能の受け手を受注 ID の勧告ロック（`pg_advisory_xact_lock`）で直列にし、`data-model.md`「出荷（`fulfillment`）」に書く。勧告ロックを足したら `spec/db/lock_sites_spec.rb` の表にも足す。起きたかと、どう閉じたかを、実装レビューの節と OI-79 の結果に書く

ダッシュボードの集計の境界（受注の状況の数え方・安全在庫と等しい在庫・期限を過ぎた出荷依頼・税抜きの合計）は、計画のときに取りまとめ役が決めた（OI-81）。

**完了条件**

```sh
bundle exec rspec packs/sales/spec/public/sales/sales_orders_spec.rb packs/inventory/spec/public/inventory/stocks_spec.rb \
  packs/fulfillment/spec/public/fulfillment/shipment_requests_spec.rb packs/billing/spec/public/billing/billable_items_spec.rb \
  spec/requests/dashboard_spec.rb spec/graphql/query_complexity_spec.rb spec/graphql/query_budget_spec.rb spec/matrix
bundle exec rspec spec/scenarios/revocation_spec.rb
bundle exec rspec packs/fulfillment/spec/concurrency/fulfillment/shipping_hold_lock_spec.rb
```

- 単体（4 つの公開 API の spec。どれもこのマイルストーンで足す）：受注の件数が 7 つの状況を 0 件も含めて返し、取消済を数える。安全在庫は、有効在庫が安全在庫より 1 小さい在庫を返し、等しい在庫を返さない。出荷期限は、今日から 7 日後の出荷依頼と期限を過ぎた出荷依頼を返し、8 日後・出荷済・取消済を返さない。未請求の合計は、請求書に結んだ明細を数えない。どれも他社の行を数えない（対照として、自社の行が数えられることを同じ example で確かめる）
- 結合（`dashboard_spec.rb`）：画面の問い合わせ `supplier_dashboard.graphql` の応答が、4 つの単体と同じ値を返す。`member` も読める
- シナリオ（`revocation_spec.rb`）：上の作るもの 2
- 複雑度（`query_complexity_spec.rb`）：画面の問い合わせのどれもが、`first` に 1 ページの件数の上限を渡しても上限に収まる。コネクションの要素の下にコネクションを入れ子にした問い合わせを渡すと、上限を超えて落ちる。いまのスキーマにはその形の型が無いので、同じ上限を持つスキーマを spec の中で作って渡す。リストの要素の下のコネクションは掛け算にならず、クエリ数の予算の spec が画面の問い合わせから外す（`graphql-schema.md`「ページングと N+1」）
- 競合（`shipping_hold_lock_spec.rb`）：上の割り込みの順で、停止中の受注に有効な出荷指示が残らない。直列にしたなら、勧告ロックを外すと落ちる。直列にしなかったなら、残らない理由を spec の説明に書く

**実装する文書の節**：`context-map.md`「取引関係の失効」「テナントと所有」、`graphql-schema.md`「読み取りの一覧」「ページングと N+1」、`data-model.md`「出荷（`fulfillment`）」、`showcase.md`「1. テナントの境界：読む 3 経路、書けないこと、失効」

---

## 見せどころを足すマイルストーンに共通すること

M27〜M31 は、業務の流れを一通り作った後に、設計判断を見せる仕組みを足す。どれも、業務機能のマイルストーンに共通すること（表・公開 API・行列テスト・監査の宣言・`schema.graphql`）にも従う。範囲を広げすぎないよう、各節の「範囲外」に挙げたものは作らない。

## M27 販売単価のバイテンポラル履歴

**目的**：販売単価を、有効期間と記録期間の 2 つの時間軸で持つ（`adr/006`）。受注側は単価の改定を前もって登録でき、入力の誤りを過去の行を書き換えずに訂正できる。発行済みの請求書について、「発行の時点で信じていた単価」と「いま分かっている単価」を示せる。

**作るもの**

- マイグレーション：
  - 拡張 `btree_gist`、表 `item_prices`（`create_tenant_table`、品目へ `add_tenant_reference`）、現在の行の排他制約、書き換えを拒むトリガー、経路 1 の `partner_read`（`data-model.md`「受注（`sales`）」「RLS」）
  - `sales_order_lines.priced_on`：照合前は空で、照合で単価と一緒に埋まる
- データの移行（`adr/001` 決定 4。マイグレーションに入れない）：rake タスク `sales:backfill_item_prices`（`lib/tasks/`）が、テナントを明示して 1 つずつ回り、公開 API `Sales::ItemPrices.backfill` を呼ぶ。`backfill` は、既存の `items.unit_price` を有効期間が `(,)` で記録期間がタスクの時刻から始まる行に写し、照合済みの受注明細の `priced_on` を受注日で埋める。現在の単価の行がある品目と、`priced_on` のある明細は飛ばすので、もう一度流しても行が増えない
- `items.unit_price` を消す順：表と列を足すマイグレーション → 移行のタスク → `items.unit_price` を `ignored_columns` に入れる → 次のマイグレーションで列を消す（strong_migrations の手順）。列を消すマイグレーションは、現在の単価の行が無い品目か、照合済みで `priced_on` の無い明細が 1 件でも残っていれば、例外で止まる。受注明細の「揃って空か揃って埋まる」CHECK 制約に `priced_on` を足すのも、このマイグレーションで行う。移行のタスクが既存の照合済みの明細を埋める前には足せないからである（OI-106）
- 公開 API `Sales::ItemPrices`：`schedule`・`correct`・`price_at`・`history`（品目ごとの、記録時点で信じていた全期間の行）・`explain(actor, sales_order_line_ids, as_of:)`。
- 単価を使う箇所の切り替え（`adr/006` 決定 5）：`Sales::Catalog`・`Sales::PublishedCatalog` は今日の単価を返す。ACL（`Sales::PurchaseOrderTranslator`）と照合のやり直し（`Sales::PartMappings.register`）は、受注日の単価を写し、`priced_on` を書く。`saveItem` の `unitPrice` は、品目を作るときは有効期間 `(,)` の行を作る。既存の品目の単価は変えず、今日の単価と違う値は役割を問わず `INVALID_INPUT` にして `scheduleItemPrice` を使うよう伝え（OI-89）、同じ値は無視する（OI-103）。
- GraphQL：`Item.prices`・`ItemPrice`・`scheduleItemPrice`・`correctItemPrice`・`BillableItem.priceExplanation`（`graphql-schema.md`「受注側の視点」「mutation の一覧」）。`scheduleItemPrice`・`correctItemPrice` は、発注側のカタログに見える単価を変えるので監査する。
- 行列テスト：`item_prices` の行（`granted_buyer` は公開品目の現在の行を読める）と、新しいフィールドと mutation の行。`scheduleItemPrice`・`correctItemPrice` は金額に関わる操作なので `admin` に限り、行は許す役割に `admin` を持つ（OI-80 で作者が決めた）。規則は `graphql-schema.md`「役割による制限」の表の `Sales::ItemPolicy#change_price?` で、`context-map.md`「自社の中の役割」と同じ表には、この 2 つを `admin` に限る操作として書いてある。`saveItem` からは、`member` も `admin` も既存の品目の単価を変えられない（OI-89）。request spec と `saveItem` の行列の行で、どちらの役割でも既存の品目の単価が変わらないことと、新しい品目が最初の単価を持つことを確かめる。
- 品目は、作るときに必ず有効期間 `(,)` の単価の行を持つ（`saveItem` と、M29 の取り込みの `Sales::Catalog.bulk_upsert`）。現在の単価の行が無い品目への `schedule` は `CONFLICT` にする。照合後に埋まる列に `priced_on` が加わるので、受注明細の「揃って空か揃って埋まる」CHECK 制約を直す。
- テスト：
  - 単体（`packs/sales/spec/public/sales/item_prices_spec.rb`）：予約・訂正・`price_at` を、有効日 × 記録時点の表で確かめる。予約を同じ有効日で 2 回流しても行が増えない。
  - 移行（`packs/sales/spec/public/sales/item_prices_backfill_spec.rb`）：`backfill` が品目と照合済みの明細を埋め、2 回流しても行が増えず、他のテナントの行に触れない。列を消した後のテストの DB には移行の前の形が無いので、所有ロールで `items.unit_price` を一時的に足し直し、CHECK 制約を外して作る（OI-106）。
  - 競合（`packs/sales/spec/concurrency/sales/item_prices_lock_spec.rb`）：同じ品目への予約どうしと、予約と訂正が、品目の行ロックで直列になる。
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

- パッケージ `packs/notifications`（`Notifications::`）。依存先は `platform`・`partnerships`（宛先のメールアドレスを自社の `users` から引く）。ルートの `package.yml` の依存先にも足す。`webhook_inbox_events` はテナントの表でないので、テナント列の列挙テストの除外に理由を書いて足す（`adr/007` 決定 5 の A-3）。`sales`・`purchasing` の依存先に `notifications` を足す。`context-map.md`「疎結合を守る規則」の依存の向きの表に `notifications` の行（`platform`・`partnerships`）を足し、`sales`・`purchasing` の行の依存先に `notifications` を足す。表は `email_deliveries` と `webhook_inbox_events`（`data-model.md`「通知（`notifications`）」）。
- `ExternalEffectJob`（`packs/platform`）と、`Notifications::CriticalDeliveryJob`・`BestEffortMailJob`・`ProcessInboxJob`（`adr/007` 決定 4〜6）。
- 公開 API `Notifications::Email.deliver_critical`・`deliver_best_effort` と、通知の種類の登録 `Notifications::Catalog`。種類は 2 つにする。
  - `received_invoice`（確実）：購買の「請求書発行」の受け手が、受領請求書を書くのと同じトランザクションで、自社の `admin` へ送る。
  - `new_sales_order`（撃ちっぱなし）：受注側が受注を確定したとき（ACL と、対応表の登録による照合のやり直しの両方）に、自社の `admin` へ送る（OI-83・OI-98）。
- メールの本文は Action Mailer のテンプレート（`Notifications::Mailer`、text だけ）で書き、送信はジョブの中で `deliver_now` を呼ぶ。
- 送信先の切り替え：`Notifications::Provider` の実装を 3 つ置き、`config.x.notifications.provider` で選ぶ。
  - `Sendgrid`：v3 の送信 API を `Net::HTTP` で呼ぶ。`Net::HTTP` の既定の時間切れ（`open_timeout`・`read_timeout`・`write_timeout` はどれも 60 秒）は `external_mail` の 2 本のスレッドを長く塞ぐので、`open_timeout` を 5 秒、`read_timeout`・`write_timeout` を 10 秒にする。`Net::OpenTimeout`・`Net::ReadTimeout`・`Net::WriteTimeout`・`SocketError` と、`SystemCallError`（`Errno::ECONNREFUSED`・`Errno::ECONNRESET` などをまとめる）・`IOError`・`OpenSSL::SSL::SSLError`・`Net::HTTPBadResponse`・`Net::ProtocolError` を、A-2 の表の「タイムアウト・接続の失敗」に当てる（OI-102）。API キーは credentials に置き、ログに書かない。本番以外の環境では、SendGrid の sandbox mode（受け付けの検査だけを行い、配信しない）を有効にしないと起動時に例外にする。
  - `FileSystem`（開発）：`tmp/mails/` に 1 通 1 ファイルで書く。
  - `Fake`（テスト）：メモリに積み、テストから読める。
- WebMock を test のグループに入れ、`spec/spec_helper.rb` で全テストに `WebMock.disable_net_connect!(allow_localhost: true)` を掛ける。
- Webhook：`Webhooks::SendgridEventsController`（ルートパッケージ）と `POST /webhooks/sendgrid/events`。セッションを使わず、署名で認証する（`adr/007` 決定 5 の A-3）。
- キューの設定：`config/queue.yml` を `adr/007` 決定 7 の 4 つのワーカーに分け、`Contracts::EventJob` を `events` に載せる。定期のジョブ（`config/recurring.yml`）に、inbox の未処理を拾う（毎分）と処理済みを消す（毎日）を足す。
- カスタム Cop `FactoryOps/ExternalEffectEnqueue` と、`spec/notifications/call_sites_spec.rb`（`adr/007` 決定 4）。
- 再送の操作 `Notifications::Email.redeliver_failed(since:)`：再試行を使い切ったか、再試行しない応答で失敗した確実な送信の `failed_at` を空に戻し（OI-99）、同じ送信記録のジョブを登録し直す。新しい送信記録は作らない。運用者は rake タスク `notifications:redeliver` から呼び、タスクはテナントを明示して 1 つずつ回る（`decisions.md` 2 章）。
- ガードテスト：`spec/jobs/event_job_atomicity_spec.rb` を広げ、`enqueue_after_transaction_commit` が `false` のクラスが `Contracts::EventJob` と `Notifications::CriticalDeliveryJob` の 2 つだけであることと、`ExternalEffectJob` のどのサブクラスもその値と保証を自分のクラスで宣言していることを確かめる。
- テスト：
  - `Sendgrid` のアダプタ：WebMock のスタブで 202・sandbox mode の 200・429（待ち時間のヘッダ付き）・500・400・401・タイムアウトを返し、`adr/007` 決定 5 の A-2 の表のとおりに分類される。200 と 202 は、メッセージ ID のヘッダが無くても受け付けとして扱う。
  - 確実な送信：同じ「請求書発行」を 2 回流しても送信記録は 1 件。購買の「請求書発行」の受け手が `deliver_critical` を呼んだ後に例外で失敗すると、受領請求書・送信記録・送信のジョブがどれも残らない。受け手のトランザクションのコミットの前に、送信のジョブが同じトランザクションの中に登録されている。受け付けの後にジョブをもう一度流しても、送らない。400 と、再試行を使い切ったときに `failed_at` が入り、`notification.delivery_failed` が出る。
  - inbox：同じ `sg_event_id` の 2 回の受信で行が 1 件。署名の誤りで 401。保存した行にメールアドレスが無い。処理を 2 回流しても、送信記録の時刻列が 1 回だけ書かれる。

**完了条件**

```sh
bundle exec rspec packs/notifications/spec spec/notifications spec/jobs spec/requests/sendgrid_webhook_spec.rb spec/rubocop
bin/rubocop
```

`bin/jobs` を動かして請求書を発行し、`tmp/mails/` に受領請求書の通知が 1 通できることを、手で確かめる。

**範囲外**：HTML のメール、配信停止の管理、通知の設定画面と宛先の選択、提供元の単位で送信を止める仕組み（`adr/007`「見直す条件」）。

**実装する文書の節**：`adr/007`、`decisions.md` 5 章、`data-model.md`「通知（`notifications`）」、`context-map.md`「コンテキスト」

**文書に残すこと**：`adr/007` の未確認の事項（OI-15）を、確かめた結果で置き換える。

## M29 大量データの取り込み

**目的**：受注側が、品目と単価、在庫の CSV（数万行）を取り込める。取り込みは、イベントの配送とメールを待たせない。途中で止まっても続きから再開し、失敗した行を報告し、進み具合を GraphQL で見せる。メモリの使用量は、ファイルの大きさの上限とチャンクの大きさで上から抑える。

**作るもの**

- パッケージ `packs/imports`（`Imports::`）。依存先は `platform`・`partnerships`・`sales`・`inventory`。ルートの `package.yml` の依存先にも足す。`context-map.md`「疎結合を守る規則」の依存の向きの表に、この行を足す。表は `imports`・`import_files`・`import_rows`（`data-model.md`「取り込み（`imports`）」）。
- ファイルの受け取り：`POST /imports/files`（`ImportFilesController`、ルートパッケージ）が `multipart/form-data` の CSV を受け取り、`import_files` に書いて ID を返す。ファイルを置くだけで、業務の表には何も起きない。10 MB を超えるファイルは受け付けない。コントローラは `GraphqlController` と同じく、セッションのユーザーと世代を確かめてから、セッションのテナントで `Tenancy.with_tenant` を開いて書く。`startImport` に他社か存在しないファイルの ID を渡すと `NOT_FOUND` になり、S1 の表に行を足す。セッションで認証し、`Origin` ヘッダが許可した origin と一致しなければ拒む。`GraphqlController` の `application/json` の制限に代わる CSRF 対策である。
- 取り込みの開始：mutation `startImport(fileId, kind)` が `imports` の行を書き、ジョブを登録する。業務の表に効果が及ぶのはここからなので、監査はこの mutation の宣言で行う。単価の列を含む CSV（種類が `items`）の取り込みは、金額に関わる操作なので `admin` に限る（OI-80 で作者が決めた）。`context-map.md`「自社の中の役割」と `graphql-schema.md`「役割による制限」の表には書いてある。種類で役割が変わるので、`startImport` を対象を引く mutation にし、対象を取り込みの依頼（置いたファイルと種類）の値にして、規則 `Imports::ImportPolicy#start?` が種類を見る（OI-91、OI-109）。ジョブも反映のチャンクごとに、取り込みを始めたユーザーのいまの役割で同じ規則を評価し直し、満たさなければ取り込み全体を失敗にする。入口の行列は、`Mutation.startImport`（品目、`admin`）と `Mutation.startImport#stocks`（在庫、役割を問わない）の 2 行を持つ。
- ジョブ `Imports::RunJob`（`adr/007` 決定 5 の A-4）：`ApplicationJob` を継承し、`ActiveJob::Continuable` を取り込む。`queue_as :imports`、`limits_concurrency to: 1, key: ->(import_id, tenant_id) { tenant_id }, duration: 1.hour`、`tenant_transaction :per_chunk`（いまの `ApplicationJob` は `around_perform` でジョブ全体を `Tenancy.with_tenant` で包むので、この宣言を `ApplicationJob` に作り、宣言したジョブでは包まない）。`limits_concurrency` の保証は `duration` の間だけで、過ぎると待っている次のジョブが動きうる（solid_queue 1.7.0 の README「Concurrency controls」。既定は `SolidQueue.default_concurrency_control_period` の 3 分）。テナントごとに 1 は、1 社が imports のワーカーを占めないための上限で、反映の正しさはこれに頼らない。同じテナントの 2 つの取り込みが並んでも、品目の upsert と単価の予約は品目の行ロックで、在庫は在庫の行ロックで直列になる。各段階の始めに、カーソルを置き場から作り直す（`stage` は `import_rows` の最大の行番号の次から、`apply` は結果の無い最小の行番号から）。同じ取り込みのジョブが 2 つ動いても結果が 1 つになるよう、どの段階もチャンクのトランザクションの初めに `imports` の行をロックし、ロックの後に置き場の状態を読み直してから書く（`data-model.md`「取り込み（`imports`）」）。そのため、継続の情報を持たない新しいジョブでも続きから進む。
  1. `step :stage`：`import_files.content` を 1 MB ずつ一時ファイルへ写し、`CSV.new` で 1 行ずつ読み、1,000 行ごとに `import_rows` へ `insert_all` で書く（OI-115）。カーソルは書き終えた行番号である。見出しの行の誤りと、50,000 行を超えるファイルは、取り込み全体の失敗（`failed_at`）にする。
  2. `step :apply`：`import_rows` を行番号の順に 500 行ずつ取り、チャンクごとに `Tenancy.with_tenant` を開いて反映する。`applied_at` か `error` のある行は飛ばす。行ごとの業務の書き込みはセーブポイントの中で行い、失敗した行の書き込みだけを戻して `error` を書く。業務の書き込み・行ごとの `applied_at` か `error`・`imports` の件数の加算（そのチャンクで新しく結果を書いた行の数だけ）を、チャンクの 1 つのトランザクションで書く。カーソルは反映したチャンクの最後の行番号である。
  3. `step :finalize`：`finished_at` を書き、`import_files` の中身を消す。
- 反映の書き方（種類ごと）：
  - **品目**：CSV の列と行ごとの検証は `data-model.md`「取り込み（`imports`）」にある（OI-82）。検証を通った行の品目の列（コード・名前・単位・税率・公開）は、公開 API `Sales::Catalog.bulk_upsert` が `upsert_all(unique_by: [:owner_tenant_id, :code])` で書く。`owner_tenant_id` には `Current.tenant_id` を明示して入れ、RLS の `WITH CHECK` が他社の名義の行を拒む。`bulk_upsert` は、新しく作った品目に、有効期間 `(,)` の単価の行を同じトランザクションで作る（`saveItem` で品目を作るときと同じ）。既存の品目の単価には `bulk_upsert` は触れない。単価の列は、取り込みが改定日の単価をチャンクごとにまとめて引き、違う行だけを `Sales::ItemPrices.schedule` で有効日からの改定として予約する（`adr/006` 決定 3）。既存の品目の単価を変える入口を、改定の予約と訂正にまとめるためである（OI-89、OI-110）。失敗する行は書く前に決めて書き込みに含めないので、品目の行には戻す書き込みが無い（OI-112）
  - **在庫**：行ごとに、在庫の行をロックしてから目標の数量との差を入庫か出庫にする公開 API（`Inventory::Adjustment.set_quantity`、目標の数量を渡す）を呼ぶ。ロックの前に読んだ数量で差を計算すると、同時の `adjustStock` や引当とずれる。`stocks` を `insert_all` で書かない。在庫の変更は `move!` を通って移動履歴を残す（`data-model.md`「在庫（`inventory`）」）。
  - `insert_all`・`upsert_all` は、モデルのコールバックとバリデーションを通らない。使ってよいのは、不変条件が DB の制約だけで閉じる表（品目・置き場の行）に限る。
- 冪等：同じチャンクを 2 回反映しても結果が 1 つになる。`applied_at` のある行を飛ばし、品目の upsert と単価の予約（同じ単価・同じ有効日なら何もしない）は、もう一度流しても変わらない。プロセスが落ちて中断点を通らなかったときに、最後に保存したカーソルからやり直すためである。
- GraphQL：`supplier.imports`・`supplier.import(id)`・`Import`・`startImport`（`graphql-schema.md`「受注側の視点」）。
- 再登録の操作 `Imports::Runs.reenqueue(import_id)`：ジョブを失って「待機中」「置き場へ写し中」「反映中」のまま残った取り込みに、新しいジョブを登録する。プロセスが強制終了したジョブは、Solid Queue が `SolidQueue::Processes::ProcessPrunedError` で失敗にし、自動では再試行しない（solid_queue 1.7.0 の README「Jobs interrupted by non-graceful process death」）。運用者は、取り込みのジョブの失敗を見てから rake タスク `imports:reenqueue` で呼ぶ。動いているジョブがある取り込みに呼んでも、新しいジョブはテナントの上限で待ち、行ごとに飛ばすので結果は変わらない。
- `bin/rails imports:sample[50000]`：試験用の CSV を作る。
- テスト：
  - 置き場（`spec/requests/imports_spec.rb`）：10 MB ちょうどのファイルを受け付け、10 MB + 1 バイトを拒む（IB-25 の試行）。`Origin` の不一致を拒む。
  - 中断と再開（ここから CSV の契約までは `run_job_spec.rb` と `runs_spec.rb`）：アダプタの `stopping?` を `stage` の途中と `apply` の途中で真にして中断させ、もう一度流すと続きから進み、全行が 1 回ずつ反映される。
  - 継続の情報を失った再開：`stage` の途中と `apply` の途中で実行を捨て、`reenqueue` で登録した新しいジョブを流すと、全行が 1 回ずつ反映され、件数が行の数と合う。
  - 件数の冪等：成功 2 行・失敗 1 行のチャンクを反映した後、カーソルを保存する前に止まったものとして同じチャンクをもう一度流しても、`applied_rows`・`failed_rows`・品目・在庫・移動履歴が増えない。
  - CSV の契約：見出しの誤りで取り込み全体が失敗する。同じ品目コードの 2 行目と、列の検証に外れた行が失敗になる。新しい品目に有効期間 `(,)` の単価の行ができる。既存の品目は、単価が変わるときだけ改定が予約される。
  - 並んだ取り込み（`packs/imports/spec/concurrency/imports/parallel_imports_spec.rb`）：同じテナントの 2 つの在庫の取り込みを 2 つの接続で同時に流しても、在庫の数量と移動履歴が行ごとに 1 回ずつになる。成功の行と失敗の行を含む同じ取り込みの 2 つのジョブを、`stage`・`apply`・`finalize` のそれぞれで 2 つの接続から同時に流しても、置き場の行・件数・品目・在庫・移動履歴が 1 つのジョブのときと同じになる。`imports` の行ロックを外すと落ちる。
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

上限の検査（ファイルの大きさの上限）は、上限 + 1 で拒否し、上限ちょうどで受け付ける両方の example を、仕様の値で書く。サイクル 02 の改善の探索で採用した規則の試行で、このマイルストーンで効いたかを判定する（IB-25）。上限は設定で差し替えず、`import_files` の CHECK 制約と同じ値の定数（`Imports::Files::MAX_BYTES`）にした。テストは仕様の値の大きさの文字列を作って書く（OI-113）。

**完了条件**

```sh
bundle exec rspec packs/imports/spec/jobs/imports/run_job_spec.rb packs/imports/spec/public/imports/runs_spec.rb \
  packs/inventory/spec/public/inventory/adjustment_spec.rb spec/requests/imports_spec.rb spec/jobs spec/scenarios/tenant_boundary_spec.rb
bundle exec rspec packs/imports/spec/concurrency/imports/parallel_imports_spec.rb
```

50,000 行の CSV を取り込み、ワーカーの常駐メモリ（`ps -o rss`）の増分が 100 MB 以内で、`supplier.import` の件数が進むのを、手で確かめる。途中で `bin/jobs` を止めて起動し直し、続きから進むことも確かめる。

**範囲外**：取り込みの取消、失敗した行だけのやり直し（利用者は失敗した行を直したファイルを送り直す）、Excel の形式、受注・発注の取り込み。

**実装する文書の節**：`adr/007` 決定 5 の A-4・決定 7、`adr/006` 決定 3、`data-model.md`「取り込み（`imports`）」「在庫（`inventory`）」

## M37 RLS が隠す scope の抜けと、読み取りの役割を行列で捕まえる

**目的**：認可の 3 段のうち scope（2 段目）は「RLS に任せない」（`architecture/graphql-schema.md`「認可」）が、相手から読む経路の無い表では、公開 API の scope を外しても RLS が他社の行を隠すので、いまのテストは落ちない（IB-35。テナントの表 40 のうち 34 がこの形）。入口の行列がこの抜けを捕まえるようにする。あわせて、行列の役割の検査を `admin` に限る読み取りにも広げる（IB-29）。どちらも業務の振る舞いを変えない。

**作るもの**

1. 試作と分かれ目：別名のテスト DB で、下の 2 の (1)〜(4) が成り立つかを先に確かめる。テストの DB にポリシーを足して外す操作が、世界の固定した接続のロックと待ち合わないこと、2 回目の入口の行列で、scope を外した入口が落ちることを確かめ、結果を証跡に書く。成り立たなければ、判断の裏返る条件に従って止め、取りまとめ役に返す
2. scope を RLS の外で確かめる（IB-35）：
   1. テストの環境でだけ、テナントの表ごとに、設定の値（`app.matrix_cross_read`）が `on` のときだけ全行を読ませる SELECT のポリシーを足す。ポリシーを作る SQL は `spec/support` にだけ置き、`lib/tenant_table.rb` とマイグレーションには置かない。アプリのロールは `app.*` の設定を自由に変えられるので、本番に載れば全テナントの行を読む抜け道になるからである。補助は、接続先がテストの DB であることを名前で確かめてから、所有ロールの接続で、世界を開く前に足し、世界を閉じた後に外す。足す途中で失敗しても、足した分を外す。補助は `MatrixWorld.share_per_file` の引数（`cross_read: true`）にし、世界を開く `before(:context)` の前に足し、世界を閉じる `after(:context)` の後に外す順を、そこで固定する。掛けるのは `graphql_matrix_spec.rb` と `matrix_world_spec.rb` で、`table_matrix_spec.rb` には掛けない。`structure.sql` に混ざったときは `bin/check-structure` が落とす
   2. 設定の値は、example のトランザクションの中で `SET LOCAL` し、ロールや DB の既定には書かない
   3. 入口の行列の読み取りの行は、同じ example の中で、設定を外した応答と `on` にした応答の本文が一致することで確かめる。結果の種類（値・空・`null`）だけを比べると、集計を返す入口（`supplier.dashboard`）で scope を外しても種類が変わらないからである。順序の決まらない一覧で誤って落ちないよう、比べる応答の並びが決まることも確かめる。比べる本文に集計の差が出るよう、行列の `SupplierView.dashboard` の問い合わせはダッシュボードのすべてのフィールド（`stocksBelowSafetyStock`・`shipmentRequestsDueSoon` を含む）を読み、`MatrixWorld` は、どのペルソナにも各集計に当たる行（有効在庫が安全在庫を下回る在庫、期限が今日から近い未出荷の出荷依頼、未請求の明細）を持たせる
   4. 2 回目が空振りしないことを確かめるガードの example を置く。設定を `on` にした生 SQL が、他社の行を読めることと、設定を `on` にしてダッシュボードの 4 つの公開 API から scope を外すと、各集計が他社の行を含んで変わることを確かめる。このガードと、足す途中で失敗しても足した分を外すことの example は `spec/matrix/matrix_world_spec.rb` に置く
   5. `spec/db/tenant_enforcement_spec.rb` に、テナントの表のポリシーの集合が `owner_write` と、読む 3 経路の 6 つの表の `partner_read` だけであることの確かめを足す。いまはどちらの spec も、足したポリシーの消し忘れを捕まえない
   6. 確かめるのは GraphQL の入口から届く読み取りだけである。GraphQL を通らない公開 API（通知の宛先・取り込みの再登録・単価の移行）は外に残り、M32 の作るもの 10 が操作者のいない入口の規則を当てる（OI-118）。完了を、公開 API 全体の所有の条件を確かめ終えたと書かない
   7. 入れ子のフィールドが親の値から取った ID で呼ぶ公開 API（dataloader の一括取得と、親の ID を渡す resolver）は、親と同じテナントの子しか引かないので、(3) の比べ方では scope の抜けが見えない。全ペルソナの ID を直に渡し、RLS の SELECT を開いても呼んだペルソナの ID にだけ値を返すことを、入口の行列で確かめる。対象は `app/graphql` の書き方から集め、行の無い公開 API があれば落とす（OI-128）
3. 行列の役割の検査を読み取りに広げる（IB-29）：読み取りの行にも許す役割（`role:`）を持たせ、全ペルソナの `member` で呼ぶ。`member` の期待は行ごとに書く（`viewer.auditLogs` は `FORBIDDEN`、`viewer.partnerCode` は `null`）。`viewer.partnerCode` は型のメソッドで書いたフィールドで、いまの列挙（`Viewer` の下のリゾルバ付きのフィールド）に入らないので、列挙に足し、入口の列挙の完全性の確かめと食い違わない形にする。「ほかの行は役割を持たない」の確かめは、全行が役割を持つ形に書き直す

**判断**：scope の抜けを、RLS の SELECT を開いた 2 回目の行列で捕まえるか

- **既定の推奨**：テストの DB にだけ設定の値で開く SELECT のポリシーを足し、入口の行列を 2 回目に流す。入口の行列の期待値と応答をそのまま使うので、入口ごとの example を足さずに全入口に効き、返った値そのものを比べる
- **比べた案**：公開 API の構文木で、テナントの表を引く呼び出しが scope を通るかを照らす案は、サブクエリで絞る形を追えず外れが多い。テストの間だけアプリのロールに `BYPASSRLS` のロールへの切り替えを許す案は、ロールがクラスタ全体のものなので、開発の DB でもアプリのロールが RLS を外せるようになる
- **裏返る条件**：作るもの 1 の試作で、ポリシーの足し外しが世界のロックと待ち合うか、2 回目の行列で scope を外した入口が落ちない → 構文木の案に移るか、IB-35 を見送りに戻す
- **撤退コスト**：小さい。補助と行列の 2 回目を外せば元に戻る。`structure.sql` は変えない。業務のコードは、2 回目が見つけた scope の抜けの直し（OI-128 の `Partnerships::Directory.user_names`）だけを変え、撤退しても残す

**完了条件**

```sh
bundle exec rspec spec/matrix spec/db/tenant_enforcement_spec.rb   # 0 failures
for seed in 1 2 3; do bundle exec rspec spec/matrix --order rand --seed $seed || exit 1; done
bin/check-structure
```

M37 は業務の振る舞いを変えないので、期待の不一致で最初に落ちるのは、`matrix_world_spec.rb` のガード（設定を `on` にした生 SQL が他社の行を読める）である。補助が無いと 0 行で落ちる。読み取りの行の `member` の期待は、仕様の値（`viewer.auditLogs` は `FORBIDDEN`、`viewer.partnerCode` は `null`）で初めから書く。ほかは、次の壊して落ちる記録を spec ごとに証跡の「実装の記録」に残す（`guides/dev-cycle.md`「テストから書く」）。

- scope：次の 6 つの公開 API から 1 つずつ scope か所有の条件を外すと、2 回目の入口の行列が落ちる。受注の一覧（`Sales::SalesOrders.list`）、在庫の一覧（`Inventory::Stocks.list`）、ダッシュボードの 4 つ（`Sales::SalesOrders.count_by_status`・`Inventory::Stocks.below_safety_stock`・`Fulfillment::ShipmentRequests.due_within`・`Billing::BillableItems.unbilled_total`）。外さなければ 0 failures（落ちたら、いまの scope の抜けとして直す）
- 2 つの守り：同じ 6 つで、RLS と scope を片方ずつ壊した結果を残す。scope を外しても 1 回目（設定を外した応答）の期待は落ちず、scope を残したまま設定を `on` にしても応答は変わらない
- ガード：空振りを確かめる example から設定を外すと落ちる。ポリシーを外さずに終えると `tenant_enforcement_spec.rb` が落ちる。足す途中で例外を起こしても、ポリシーが残らない
- 役割：`Platform::AuditLogPolicy#index?` から `admin?` を外す、`Types::ViewerType#partner_code` の `admin?` を外す、役割を問わない読み取りの規則に `admin?` を足す、のそれぞれで入口の行列が落ちる
- 行列の 2 ファイルの時間を、変える前と後で証跡に書く（手元。流したコマンドと commit を添える）

**範囲外**：GraphQL を通らない公開 API の所有の条件（OI-118）、表の行列（生 SQL で RLS を確かめる。変えない）

**実装する文書の節**：`guides/testing.md`「行列テストとの分担」、`architecture/graphql-schema.md`「役割による制限」

**文書に残すこと**：2 回目の入口の行列と、ポリシーの足し外しを、行列の spec の「別の接続を使わない」の例外として `guides/testing.md`「行列テストとの分担」に書く。読み取りの行の役割を `graphql-schema.md`「役割による制限」の行列の段落に書く。

## M30 メトリクス

**目的**：GraphQL の操作の時間、キューの滞留と待ち時間、イベントの配送の遅れ、外部の呼び出しの失敗と 429、取り込みの速さを、数値で測れる。メトリクスのラベルに、テナントとユーザーを入れない。

**作るもの**

1. `yabeda`・`yabeda-prometheus`・`webrick`。`yabeda-prometheus` 0.9.1 は `prometheus-client` を 5 未満に限るので、`prometheus-client` は 4 系になる。exporter（`Yabeda::Prometheus::Exporter.start_metrics_server!`）は Rack 3 では `Rackup::Handler::WEBrick` で立つが、`webrick` は依存に無いので Gemfile に足す（yabeda-prometheus 0.9.1 の `lib/yabeda/prometheus/exporter.rb`）。メトリクスの定義は `config/initializers/metrics.rb` の 1 か所に置く。
2. 値の出どころは、M18 の `Rails.event` の購読者 `Platform::MetricsSubscriber` の 1 つにする。キューの滞留だけは、収集の時点で Solid Queue の表を数える。表の「足すイベント」の列が空でない行は、いまのコードがそのイベントを出していないか、項目が足りないので、このマイルストーンで足す。足したイベントと項目は、`guides/config.md`「イベントごとに書く項目」にも書く。購読者を足すと、購読者を `Platform::JsonLogSubscriber` の 1 つに固定している `spec/platform/logging_spec.rb` の確かめが落ちるので、2 つにする。

   イベントの値は次のとおりに写す。時間の項目はミリ秒なので秒に直す（`active_job.completed` の `duration` は activejob 8.1.4 の `lib/active_job/structured_event_subscriber.rb` で `event.duration.round(2)`）。`active_job.started` の `enqueued_at` は ISO 8601 の文字列なので、時刻に直してから差を取る。`graphql.operation_completed` の `result` の `success` はラベル `outcome` の `ok` にする。ヒストグラムのバケットは、M31 の SLO の閾値が `le` の境界になるように、表の「バケット（秒）」の列で決める。指定しないと `prometheus-client` の既定（最大 10 秒）になり、60 秒・300 秒・900 秒の割合を取れない（yabeda-prometheus 0.9.1 の `lib/yabeda/prometheus/adapter.rb` の `register_histogram!`）。

   | メトリクス | 種類 | ラベル | バケット（秒） | 出どころ | 足すイベント |
   |---|---|---|---|---|---|
   | `graphql_operation_duration_seconds` | ヒストグラム | `operation`・`operation_type`（`query`・`mutation`。決まらない文書は `none`。OI-129）・`outcome`（`ok`・`user_error`・`error`） | 0.05・0.1・0.25・0.5・1・2.5・5・10 | `graphql.operation_completed` の `result`・`duration_ms` | 操作の種類（`operation_type`）を足す。`FactoryOpsSchema.execute` が例外を上げたときも、`ensure` で `result` を `error` にして 1 回だけ出してから、例外を上げ直す。いまは正常に戻ったときだけ出すので、500 になった操作が成功の割合の分母から抜ける |
   | `graphql_top_level_errors_total` | カウンタ | `operation`・`code`・`reason` | — | 同上 | トップレベルのエラーの `extensions.code` の一覧（`error_codes`）と、`FORBIDDEN` の出どころ（`forbidden_reasons`）を足す。出どころは、操作の規則の拒否（役割を含む。`AuthorizationDeclarations` の `enforce_rule!`）を `rule`、返すオブジェクトとフィールドの規則の拒否（`FactoryOpsSchema.unauthorized_object`・`unauthorized_field`。scope と規則の食い違い）を `object`、宣言の無い型・リゾルバ・mutation の拒否を `undeclared` とし、拒否した箇所が `result.context` に積む。`FORBIDDEN` のほかのコードの `reason` は `none` にする（OI-124） |
   | `job_duration_seconds` | ヒストグラム | `queue`・`job_class` | 0.1・0.5・1・5・30・60・300・900・3600 | `active_job.completed` の `duration` | |
   | `job_queue_latency_seconds` | ヒストグラム | `queue` | 0.5・1・5・15・60・300・900 | `active_job.started`（受け取った時刻 − `enqueued_at`） | |
   | `event_delivery_lag_seconds` | ヒストグラム | `event` | 1・5・15・60・300・900 | `contracts.event_handled` の `delivery_lag_ms` | |
   | `queue_ready_jobs`・`queue_blocked_jobs`・`queue_claimed_jobs`・`queue_failed_jobs` | ゲージ | `queue` | — | 収集の時点で `solid_queue_ready_executions`・`solid_queue_blocked_executions`・`solid_queue_claimed_executions`・`solid_queue_failed_executions` を数える。ワーカー側の exporter だけが数える（作るもの 4）。`claimed` は実行中のジョブで、M31 の取り込みの停滞の警報が使う | |
   | `external_requests_total` | カウンタ | `provider`・`status`（`2xx`・`429`・`4xx`・`5xx`・`timeout`） | — | `notifications.provider_responded` | `Notifications::Provider::Sendgrid#deliver` が、応答の状態コードを分けた値か、`CONNECTION_ERRORS` のときの `timeout` を出す |
   | `notification_acceptance_seconds` | ヒストグラム | `kind` | 5・30・60・300・900・3600 | `notification.accepted`（受け付けの時刻 − 送信記録の作成時刻） | `Notifications::CriticalDeliveryJob` が `accepted_at` を書いた後に出す |
   | `notification_failures_total` | カウンタ | `kind`・`reason` | — | `notification.delivery_failed` | |
   | `notification_dropped_total` | カウンタ | `kind`・`reason` | — | `notification.best_effort_dropped` | |
   | `import_rows_total` | カウンタ | `kind`・`result`（`applied`・`failed`） | — | `imports.chunk_applied` の `applied_rows`・`failed_rows` | |
   | `import_duration_seconds` | ヒストグラム | `kind`・`size`（10,000 行以下は `small`、超えれば `large`） | 10・30・60・300・900・3600 | `imports.finished` の `duration_ms`・`total_rows` | |

3. ラベルの規則：テナント ID・ユーザー ID・伝票の ID をラベルにしない。値の種類が増え続けて保存が膨らみ、メトリクスの基盤にテナントの情報が流れるからである。テナントごとの調査は、ログ（相関 ID）で行う。`operation` には、クライアントが自由に付ける `operationName` をそのまま使わない。`config/graphql_operations.yml` に登録した名前だけを使い、それ以外は `other` にする。登録の表は `queries` と `mutations` の 2 つに分ける。`queries` は、M17 の画面の問い合わせの一覧（M33 で `frontend/graphql/` に移した）の query の操作名と一致させる。`mutations` は、画面が送る mutation の操作名を書き、M31 の SLO が測る発注の登録（`PlacePurchaseOrder`）をこのマイルストーンで足す。M33 で一覧を `frontend/graphql/` に移してからは、一覧に mutation の文書も置き、`mutations` を mutation の文書の操作名と一致させる。
4. 公開の仕方：`yabeda-prometheus` の exporter を、Web とワーカーでそれぞれ 1 つずつ、別のポート（9394・9395）で立てる。ポートは内部のネットワークにだけ開き、公開のロードバランサーに出さない。Rails のルートには `/metrics` を置かない。exporter はポートを `PROMETHEUS_EXPORTER_PORT`（無ければ `PORT`）で、アドレスを `PROMETHEUS_EXPORTER_BIND`（無ければ `0.0.0.0`）で決め、引数では渡せない（`exporter.rb`）。`PORT` は Puma も使うので、exporter を立てるプロセス（`METRICS_PROCESS` を示したプロセス。OI-133）では `PROMETHEUS_EXPORTER_PORT` を必ず設定し、無ければ起動を止める。
   - Web：Puma の起動のフック（`config/puma.rb`）で立てる。初期化子に置くと、`config/environment` を読む `bin/jobs`・rake タスク・console でも立つからである
   - ワーカー：`bin/jobs` は、supervisor が worker・dispatcher・scheduler を別のプロセスに fork するので、exporter は supervisor が fork の前に呼ぶ `SolidQueue.on_start` で 1 つだけ立てる（solid_queue 1.7.0 の README「Lifecycle hooks」）
   - 値の置き場：どちらのプロセスも `prometheus-client` の `DirectFileStore` に書く。store はメトリクスを登録する時点で決まる（`adapter.rb` の `store_settings`）ので、ディレクトリは Yabeda の設定より前（初期化子）に、プロセスの種類を表す環境変数（`METRICS_PROCESS`：`web`・`jobs`）で選ぶ。ディレクトリを空にするのは、exporter を持つプロセスが fork の前に 1 回だけ行う（Puma の起動のフックと `SolidQueue.on_start`）。初期化子で空にすると、後から起きた別のプロセスが動いている値を消す
   - キューのゲージ：収集のブロック（`Yabeda.configure` の `collect`）は、`METRICS_PROCESS` が `jobs` のときだけ登録する。どちらの exporter の読み出しでも収集のブロックは動くからである。ゲージは supervisor の 1 つのプロセスだけが書くので、集計は `aggregation: :most_recent` にし、`pid` のラベルを付けない
   - test の環境では exporter を立てない（M33 の E2E は test の環境で `bin/jobs` を起こす）
5. `spec/platform/metrics_subscriber_spec.rb`：構造化イベントごとに、対応するメトリクスが増える。登録していない `operationName` は `other` になる。登録の表の `queries` と画面の問い合わせの一覧の操作名が一致する。ヒストグラムごとに、M31 の SLO の閾値がバケットの境界にあり、閾値ちょうどの値と閾値を超える値が別の `le` に数えられる。定義したすべてのメトリクスのラベルに、`tenant`・`user`・`_id` で終わる名前が無い。足したイベントは、`spec/requests/graphql_entry_spec.rb`（`error_codes` と `forbidden_reasons`。`member` が `admin` に限る mutation を呼ぶと `rule`、scope と規則が食い違う型を返すと `object`。登録した操作の実行中に例外を起こすと、HTTP は失敗し、`result` が `error` のイベントが 1 回出る）と、`packs/notifications/spec/models/notifications/provider/sendgrid_spec.rb`（`notifications.provider_responded`）・`packs/notifications/spec/jobs/notifications/critical_delivery_job_spec.rb`（`notification.accepted`）で確かめる。
6. サイクル 03 の逸脱検査から送った確かめ：mutation の戻り値の null の伝わり方（OI-119）を `spec/requests/mutation_payload_spec.rb` で、`unitPrice` に `bigint` の最大値ちょうどと最大値 + 1（`"9223372036854775807"`・`"9223372036854775808"`）を送ったときの結果（OI-121）を `spec/requests/item_prices_spec.rb`（`scheduleItemPrice`・`correctItemPrice`）と `spec/requests/catalog_spec.rb`（`saveItem`）で確かめる。確かめた結果に、`graphql-schema.md` の SDL か実装を合わせる（実装を SDL に合わせた。OI-130）。最大値 + 1 がトップレベルのエラーになるなら、公開 API の検証に上限を足し、取り込みの CSV の同じ値を行の失敗にする（`packs/imports/spec`）。

**判断**：Yabeda と Prometheus にするか、OpenTelemetry にするか

- **既定の推奨**：Yabeda と Prometheus にする。メトリクスを 1 か所の Ruby の定義から出し、Prometheus が引きに来る形なので、収集器（Collector）を立てずに手元とデモで確かめられる。OpenTelemetry の Ruby のメトリクスの SDK は、まだ安定版でない。
- **裏返る条件**：分散トレースが要る（別のサービスが増える）か、組織の監視基盤が OTLP で受ける → OpenTelemetry に移る。
- **撤退コスト**：小さい。値の出どころは `Rails.event` の購読者の 1 つなので、出口のライブラリを替えるだけで済む。

> opentelemetry-metrics-sdk の最新は 0.20.0 で、1.0 に達していない（2026 年 10 月に rubygems.org で確かめた）。

**完了条件**

最初に落とすテストは、`metrics_subscriber_spec.rb` の「`graphql.operation_completed` で `graphql_operation_duration_seconds` が増える」example（メトリクスの定義を空のままにして、期待の不一致で落とす）と、`mutation_payload_spec.rb`・`item_prices_spec.rb` の OI-119・OI-121 の example である。OI-119・OI-121 の example は、いまの振る舞いを確かめる段階では通りうるので、通ったら、確かめた振る舞いを SDL か実装に合わせた後に、合わせた側を壊して落ちる記録を残す。

```sh
bundle exec rspec spec/platform/metrics_subscriber_spec.rb spec/platform/logging_spec.rb spec/requests/graphql_entry_spec.rb \
  spec/requests/mutation_payload_spec.rb spec/requests/item_prices_spec.rb spec/requests/catalog_spec.rb \
  packs/notifications/spec packs/imports/spec
```

`spec/platform/logging_spec.rb` も流す（購読者を 2 つにした確かめ）。`PROMETHEUS_EXPORTER_PORT=9394 METRICS_PROCESS=web bin/rails server` で GraphQL の問い合わせを 1 回流し、`curl -s localhost:9394/metrics | grep graphql_operation_duration_seconds_bucket` に値が出ることを、`PROMETHEUS_EXPORTER_PORT=9395 METRICS_PROCESS=jobs bin/jobs` を起こしてイベントを 1 件流し、`curl -s localhost:9395/metrics | grep -E 'job_duration_seconds_count|queue_ready_jobs'` に値が出て、`queue_ready_jobs` に `pid` のラベルが無いことを、手で確かめる。

**範囲外**：分散トレース、ダッシュボードの定義、ログの集約基盤。

**実装する文書の節**：M18 の構造化イベント、`adr/007` 決定 7（キュー）

**文書に残すこと**：exporter のポートとネットワークの制限と、ワーカーの値の書き方（`DirectFileStore` と `SolidQueue.on_start`）を `guides/config.md`「メトリクス」に（OI-133）、足したイベントと項目を `guides/config.md`「イベントごとに書く項目」に書く。`FORBIDDEN` の出どころの分け方を `graphql-schema.md`「エラー」に書く。

## M31 SLO と障害対応の手順書

**目的**：主な操作に SLO を決め、M30 のメトリクスで測り、外れそうなときに警報を出す。主な障害には手順書があり、どの警報からも手順書へたどれる。

**作るもの**

- SLO（`docs/slo.md`）。値は初めの目安で、30 日の実測の後に見直す。

  | SLI | 測り方（M30 のメトリクス） | SLO（28 日） |
  |---|---|---|
  | 発注の登録の速さ | `operation="PlacePurchaseOrder"`（M30 で登録の表の `mutations` に足した発注の登録）の `graphql_operation_duration_seconds` が 500 ms 以内の割合 | 95% |
  | 発注の登録の成功 | 同じ操作で `outcome` が `error` でない割合 | 99.5% |
  | 画面の問い合わせの速さ | `operation_type="query"` で `operation` が `other` でない操作が 1 秒以内の割合 | 95% |
  | イベントの配送の遅れ | `event_delivery_lag_seconds` が 60 秒以内の割合 | 99% |
  | 確実な通知の受け付け | `notification_acceptance_seconds{kind="received_invoice"}` が 15 分以内の割合 | 99% |
  | 取り込みの完了 | `import_duration_seconds{size="small"}` が 5 分以内の割合 | 95% |

- 警報の規則（`config/prometheus/alerts.yml`）：
  - **誤差の予算の消費**：SLO ごとに、1 時間で 28 日の予算の 2% を消費する速さ（13.44 倍）で呼び出し、6 時間で 5%（5.6 倍）でチケットにする。倍率は、消費する割合 × SLO の期間の時間数（28 日 = 672 時間）÷ 窓の時間数で、SLO の期間を変えたら倍率も直す。
  - **状態の警報**：`queue_failed_jobs` が 10 分続けて 0 より大きい。`queue_ready_jobs{queue="events"}` が 5 分続けて 1,000 を超える。`notification_failures_total{kind="received_invoice"}` が増えた。`external_requests_total{status="429"}` の割合が 10 分続けて 20% を超える。`graphql_top_level_errors_total{code="FORBIDDEN",reason=~"object|undeclared"}` が増えた（返すオブジェクトの規則の拒否は scope と規則の食い違いで、テナントの境界の不具合の兆しである。宣言の無い拒否は、宣言を忘れた入口が本番に出た兆しである。`member` が `admin` に限る操作を呼んだ `reason="rule"` は、画面がボタンを隠していても起こりうる利用者の操作なので、警報にしない）（OI-124）。`imports` のキューに実行中のジョブがある（`queue_claimed_jobs{queue="imports"} > 0`）のに、`import_rows_total` の合計が 15 分増えない。
  - どの警報も `annotations.runbook` に手順書のパスを持つ。発注の登録と画面の問い合わせの予算の消費は、下の 4 つの手順書のどれにも当たらないので、5 つ目の手順書 `graphql-degradation.md` を指す（OI-134）。警報の重さ・窓と、カウンタの「増えた」と取り込みの停滞の式は OI-136 にある。
- 警報の規則のテスト（`config/prometheus/alerts_test.yml`）：`promtool test rules` で、次の警報が条件を満たした系列で発火し、満たさない系列で発火しないことを確かめる。イベントのキューの滞留と、確実な通知の失敗。`FORBIDDEN`（`reason="object"` で発火し、`reason="rule"` では発火しない）。取り込みの停滞（実行中のジョブが無い・実行中で行が増える・実行中で 15 分増えない、の 3 つの系列のうち最後だけで発火する）。誤差の予算の消費の 1 つ（倍率の境目の前後）。
- `bin/check-alerts`：`promtool check rules` と `promtool test rules` を、`prom/prometheus` のイメージの `docker run` で流す。CI のワークフローはこのスクリプトを呼び、`implementation-plan.md`「共通の完了条件」の一覧と `config/ci.rb` の工程にも足す。ワークフローに `docker run` を直に書くと、`spec/platform/ci_checks_spec.rb` が照らす `bin/` のコマンドに入らず、手元の完了条件から漏れる。
- 取り込まれないファイルの後始末（OI-116）：置いてから 24 時間を過ぎても `startImport` されないファイルの中身を、定期のジョブ `Imports::PurgeAbandonedFilesJob`（`config/recurring.yml`、1 時間ごと）が消す（OI-122）。ジョブは `tenants` の ID を順に読み、テナントごとに `Tenancy.with_tenant` を開いて公開 API `Imports::Files.purge_abandoned` を呼ぶ（`notifications:redeliver` と同じ回り方）。公開 API は操作者のいない入口なので、その規則（`graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」）に従う。`Tenancy.require_tenant!` を通し、所有の条件を `Current.tenant_id` で明示し、レコードではなく消した件数を返す。後始末と `startImport` の競合は、ファイルの行ロックで直列にする。後始末は、候補のファイルの行を `FOR UPDATE` でロックしてから、別の文でそのファイルを使う取り込みが無いことを確かめ直して中身を消す。`Imports::Runs.start` も、取り込みの行を書く前に同じファイルの行をロックし、中身が消えていれば `CONFLICT`（`path` は `["fileId"]`、置き直しを促す文言）を返す。取り込みを終えて中身を消したファイルの 2 回目は、取り込み済みの `CONFLICT` を先に返す（OI-137）。READ COMMITTED では文ごとに新しいスナップショットを取るので、ロックを待った後の確かめ直しは、先にコミットした取り込みを見る。消すまでの時間・回り方・ロックの順と、消えたファイルへの `startImport` の結果を `data-model.md`「取り込み（`imports`）」と `graphql-schema.md`「mutation の一覧」に書く。単体は `packs/imports/spec/jobs/imports/purge_abandoned_files_job_spec.rb` で、24 時間ちょうどのファイルは残り、24 時間 + 1 秒のファイルは消え、取り込み中のファイルと他社のファイルは消えないことを確かめる。競合は `packs/imports/spec/concurrency/imports/purge_lock_spec.rb` で、後始末が先にロックした順と開始が先にロックした順の両方を `hold_open` の決まった順で流し、開始が成立したファイルの中身が残り、消えたファイルへの開始が `CONFLICT` になることを確かめる。足したロックを取る箇所は `spec/db/lock_sites_spec.rb` の表にも足す。
- 手順書（`docs/runbooks/`）：各手順書は「警報 → 確かめること（流すコマンド）→ 止血 → 復旧 → 事後にすること」の順に書く。

  | 手順書 | 障害 | 止血と復旧の要点 |
  |---|---|---|
  | `queue-backlog.md` | キューが詰まる | キューごとの滞留と失敗を数え、ワーカーのプロセスを確かめる。キューはワーカーを分けている（`config/queue.yml`）ので、`events` が `imports` を待つことは無い。DB の負荷が原因なら、`imports` のキューを止めて（`SolidQueue::Queue.find_by_name("imports").pause`）新しいジョブの受け取りを止める。実行中のジョブは止まらない。原因を直してから、失敗したジョブをやり直す。受け手は冪等なので、やり直してよい |
  | `sendgrid-outage.md` | SendGrid の障害・429 の連続 | 応答の種類の内訳を見る。401・403 なら API キーを確かめる。429 が続けば `external_mail` のキューを止め、待ち時間のヘッダが過ぎてから再開する。同時実行の上限はジョブのクラスに書いた値（`limits_concurrency`）なので、下げるにはデプロイが要る。再試行を使い切った確実な通知は、`notifications:redeliver` で送り直す |
  | `import-stuck.md` | 取り込みが進まない | 取り込みの行の状況と、ジョブの有無を見る。ジョブを失った「待機中」の取り込みは、`imports:reenqueue` で登録し直す。中断を繰り返していれば、取り込みの ID でログを引く |
  | `graphql-degradation.md` | GraphQL の操作が遅いか失敗する（OI-134） | 操作ごとの時間とトップレベルのエラーのコード、DB の長い問い合わせとロックの待ちを見る。デプロイの後からなら前の版に戻し、取り込みが DB に負荷をかけていれば `imports` のキューを止める |
  | `rls-misconfiguration.md` | RLS の設定の誤りが疑われる | アプリの接続のロール（`pg_stat_activity`）、ロールの属性（`rolbypassrls`・`rolsuper`）、`relforcerowsecurity` とポリシーを `structure.sql` と比べる。疑いが消えるまで、メンテナンスの切り替え（環境変数 `MAINTENANCE_MODE`）で GraphQL とファイルの受け口を 503 にする。ログインと SendGrid の Webhook は止まらない。ワーカーは止まらないので、`bin/jobs` も止める。影響を受けたテナントは、監査ログとログの相関 ID で洗い出す |

- メンテナンスの切り替え：`MAINTENANCE_MODE` が立っていれば、`GraphqlController` と `ImportFilesController`（`POST /imports/files`）は実行せずに 503 を返す。値の読み方と、止める前の検査の順は OI-135 にある。ログイン（`SessionsController`）と SendGrid の Webhook は止めない。Webhook は受信の表に書くだけで、止めると配信結果を失うからである。`spec/requests/maintenance_mode_spec.rb` で、立てたときは GraphQL とファイルの受け口が 503 で何も書かれず、ログインは通り、立てないときは同じ要求が成功の状態コード（GraphQL は 200、ファイルの受け口は 201）になることを確かめる。
- `spec/platform/alerts_runbook_spec.rb`：`alerts.yml` のどの警報も `runbook` を持ち、そのファイルが `docs/runbooks/` にあることを確かめる。

**完了条件**

最初に落とすテストは、`alerts_runbook_spec.rb`（`alerts.yml` が無い状態で、警報の一覧が空でないことの期待で落とす）、`maintenance_mode_spec.rb`（503 の期待）、`purge_abandoned_files_job_spec.rb`（24 時間 + 1 秒のファイルの中身が消える期待）である。

```sh
bin/check-alerts
bundle exec rspec spec/platform/alerts_runbook_spec.rb spec/platform/ci_checks_spec.rb spec/requests/maintenance_mode_spec.rb \
  spec/db/lock_sites_spec.rb packs/imports/spec
```

`promtool` のイメージの版は、`bin/check-alerts` に固定して書く。各手順書の「確かめること」のコマンドを、開発環境で 1 回ずつ流して動くことを、手で確かめる。

**範囲外**：オンコールの当番表、外部の死活監視、ステータスページ。

**実装する文書の節**：M30 のメトリクス、`adr/007`（キューと送信の失敗）、`data-model.md`「RLS」

**文書に残すこと**：SLO を見直したら `docs/slo.md` と `alerts.yml` を同じ変更で直す。

---

## M32 シードデータ

**目的**：デモを開いた人が、両方の視点と 3 つの読む経路をすぐ見られる。

**作るもの**

1. 世界の作り方 `DemoWorld`（`lib/demo_world.rb`）と、それを呼ぶ `db/seeds.rb`。M33 の E2E の世界（`bin/rails e2e:prepare`）も同じ `DemoWorld` で作る。シードと E2E の世界を別々に書くと、片方だけが古くなる。`DemoWorld.build(namespace:, variant:)` は次の契約を持つ。
   - `namespace`：テナントのコード・会社名の接尾辞・メールアドレスの接尾辞に入れる文字列。テナントのコード・ユーザーのメールアドレスは DB 全体で一意なので、同じ DB に複数の世界を作るときは別の値を渡す。シードは空の文字列を渡す。取引用コードも DB 全体で一意だが、推測できない無作為の値にする（`data-model.md`「取引関係と権限付与（`partnerships`）」）ので、`namespace` を入れずに世界ごとの乱数で作る（OI-139）
   - `variant`：`:seed` か `:e2e`。`:e2e` は、シードの中身に加えて、M33 が求める中身の違うデータ（最も長い品目名と取引先名、ボタンのある行と無い行、状況の enum の止まっていられる全値の行）を足す。発注の「送信済み」と取り込みの「待機中・置き場へ写し中・反映中」は、ジョブが次の状況へ進めるので含めない（OI-138）。アカウントの一覧の形と名前の付け方は OI-139 による
   - 返り値：作ったテナントの ID とアカウント（ペルソナごとのメールアドレスとパスワード）。M33 の E2E は、これでログインする
   - 冪等：同じ `namespace` の受注側のテナントがあれば、何も作らずに、あるテナントとアカウントを返す。冪等は `namespace` ごとに判定する
2. 中身：受注側に青嵐精機工業、発注側に架空の組立メーカー 2 社（全権限の付与ありと、失効済み）を作る。流用元（factory-ops-demo の `958de71`）の `backend/internal/seed/default.go` から品目（`ITM-001`〜`ITM-020`、単価・安全在庫・初期在庫）を写し、発注側の 2 社の名前に得意先の `CUS-001`・`CUS-002` を使う（OI-123）。得意先の住所と担当者、ほかの 3 社は写さない。本デモの得意先はテナントで、住所と担当者を持たないからである。受注・出荷・検収・請求書の確定まで進んだ取引と、途中の取引を混ぜる。品目には、単価の改定の予約と訂正を 1 件ずつ含める。取り込みも 1 件（一部の行が失敗したもの）含める。
3. 日付：発注日・検収日・請求書の発行日は、公開 API が `Date.current`・`Time.current`（日本時間、作るもの 9）で決める。シードはこれを動かさず、シードを流した日の日付にする。入力で渡す日付（希望納期 `desired_delivery_on`・出荷日 `shipped_on`・単価の改定日）だけを、今日からの差で書く。流用元のように受注日を過去にずらすことはしない。表へ直接書くことになるからである。
4. 書き方：シードは公開 API とイベントを通して作り、業務の表へ直接書かない。公開 API は、テナントごとに `Tenancy.with_tenant` を開き、そのテナントの `admin` のユーザーを操作者にして呼ぶ。各段の後に、登録済みのジョブのうち、イベント（`Contracts::EventJob`）と取り込み（`Imports::RunJob`）を、発行元のトランザクションの外で古い順に実行し、無くなるまで繰り返す（`spec/support/events.rb` の `deliver_enqueued_events` と同じく `solid_queue_jobs` の行を読み、`ActiveJob::Base.execute` で動かす）。テストと違い、シードは巻き戻らないので、実行した後の後始末を Solid Queue のワーカーと同じ順で行う。1 つのトランザクションで、ジョブの `ready_execution` を消して `finished!` にし、その後で `unblock_next_blocked_job` を呼んで同時実行の制御（`Imports::RunJob` の `limits_concurrency`）のセマフォを返す（solid_queue 1.7.0 の `app/models/solid_queue/claimed_execution.rb` の `finished`・`finalize`）。`finished!` だけでは、実行待ちの行とセマフォが残り、`bin/jobs` が同じジョブをもう一度動かし、同じテナントの次の取り込みが `duration`（1 時間）まで待たされる。通知のジョブは実行せず、`bin/jobs` に任せる（開発の配送先は `tmp/mails/`）。この流し方を `DemoWorld` に置き、`spec/support/events.rb` もそれを呼ぶ形にして 1 つにする。
5. 公開 API が無い 2 つの書き込み：いまはテナントとユーザーを作る公開 API と、安全在庫を設定する公開 API が無い（テストは factory で表へ書く）。次の 2 つを足す（OI-125）。
   - `Partnerships::Onboarding.register(name:, code:, partner_code:, users:)`：テナントと、`admin`・`member` のユーザーを作り、テナントの ID を返す。テナントがまだ無いので、操作者を取らず、テナントの設定の外で呼ぶ（`tenants` への書き込みは追加だけを許す、`data-model.md`「RLS」）。操作者のいない入口の規則のうち、`Tenancy.require_tenant!` だけを通さない例外である（`graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」）。ユーザーは作ったテナントの `Tenancy.with_tenant` の中で書く。`production` の環境では呼べない（例外）。サインアップの入口ではなく、シードと E2E の準備のためのものである
   - `Inventory::Stocks.set_safety_stock(actor, item_id:, safety_stock:)`：自社の在庫の安全在庫を変える。所有の条件を scope で明示する。役割は問わない（在庫の調整 `adjustStock` と同じ）。GraphQL の入口は足さない
   - `DemoWorld` が冪等を判定するために、`Partnerships::Onboarding.tenant_id(code:)` も足す。行の無いときと上限の扱いは OI-140 による
   - どちらも単体の spec（`packs/partnerships/spec/public/partnerships/onboarding_spec.rb`・`packs/inventory/spec/public/inventory/stocks_spec.rb`）で、他社の行を書けないこと（生 SQL の対照つき）と、`production` で呼べないことを確かめる
6. 境界：`lib/demo_world.rb` はルートパッケージに属し、各パッケージの `app/public` だけを呼ぶ（packwerk の privacy）。業務の表へ直接書かないので RLS と policy を通り、GraphQL の入口を足さないので入口の行列の行は増えない。作るもの 5 の 2 つの公開 API は GraphQL を通らない入口なので、表の行列（生 SQL）と単体で確かめる。
7. 役割の制限：シードは GraphQL を通らない入口なので、`admin` に限る操作（`graphql-schema.md`「役割による制限」の表の、取引関係・取消・検収・請求・単価の改定と訂正・品目の取り込み）の公開 API を呼ぶ前に、mutation と同じ policy の規則を操作者で評価し、拒否なら例外で止める（同じ節の、GraphQL を通らない入口の規則）。
8. アカウント：シードのアカウント（メールアドレスと、共通のパスワード）を `db/seeds/demo_accounts.json` の 1 か所に置き、`DemoWorld` はそこから読む（`namespace` を接尾辞として足す）。M33 のログインの画面がこの一覧を並べるか（OI-09）にかかわらず、ここに置く。パスワードはデモの手元で使う値で、本番の資格情報を書かない。シードは `production` の環境では動かない。
9. 業務の今日（OI-117）：作るもの 1〜8 より先に作る。シードと画面に出る日付が、これで決まるからである。
   - `config/application.rb` で `config.time_zone = "Asia/Tokyo"` にする。業務の日付は、どれも `Date.current`（と `Time.current` の日付）で決め、日本時間の今日になる（`context-map.md`「検収と請求の流れ」）。ダッシュボードのリゾルバの `Time.current.in_time_zone("Asia/Tokyo")` を外し、`Date.current` にする（`graphql-schema.md`「読み取りの一覧」）
   - 既存の行は書き換えない。時刻の列は Rails が UTC で書く（`ActiveRecord.default_timezone` の既定）ので変わらず、日付の列（受注日・検収日など）は書いたときの日付のまま残る。DB のセッションの時刻帯は UTC のままにし、SQL で今日を取らない（いまの SQL に `CURRENT_DATE`・`now()::date` は無い）
   - 時刻帯を混ぜる呼び出しを止める：`.rubocop.yml` で `Rails/Date` と `Rails/TimeZone` を有効にし、`Date.today`・`Time.now`・`Time.parse` などシステムの時刻帯で決まる呼び出しを落とす。`spec/rubocop/` に、2 つの Cop が有効であることを確かめる example を足す
   - テストの時刻の比較：`spec/requests/dashboard_spec.rb` に、日本時間の 0〜9 時（UTC の前日の 15〜24 時）に `travel_to` で受注を作り、受注日とダッシュボードの `businessDate` がどちらも日本時間の日付で一致する example を足す。`packs/purchasing/spec`・`packs/sales/spec`・`packs/billing/spec`・`packs/imports/spec` の、日付を決める公開 API（発注日・受注日・検収日・発行日・単価の有効日・取り込みの改定日）に、同じ境目の example を 1 つずつ足す。UTC を前提に書いた既存の比較は、全件を流して落ちたものを日本時間の今日で書き直す
   - 影響：シードの日付（作るもの 3）と M33 の画面の日付は、どれも日本時間の今日になる。`guides/config.md`「application.rb で変えたこと」に時刻帯を書く
10. 操作者のいない入口の規則（OI-118）：`graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」の規則に合わない既存の公開 API を直す。対象は `Partnerships::Recipients.admin_ids`・`emails`、`Partnerships::Authentication.acting_user`・`actor`、`Notifications::Email` の 3 つの操作、`Imports::Runs.reenqueue`、`Sales::ItemPrices.backfill` と、イベントの受け手（`Contracts::Subscriptions` の配送表に並ぶ受け手）である。実装者は、操作者を取らない公開 API を `app/public` から列挙し、証跡の「実装の記録」に一覧を残してから直す。それぞれ、`Tenancy.require_tenant!` を通し、所有の条件を `Current.tenant_id` で明示し、レコードを返しているものは ID・件数・真偽値・値に替える。認証の `actor`・`acting_user` は `Tenancy.with_tenant` の中で呼ぶので、同じ規則を当てる。テナントが決まる前のログイン（`authenticate`）は、規則の例外として直さない。
    - RLS が他社の行を隠すので、所有の条件を外しても単体は落ちない。直した公開 API の単体は、M37 の補助（設定 `app.matrix_cross_read` で開く SELECT のポリシー）を `before(:context)` で掛け、設定を `on` にした example で、他社の行を数えないことと、条件を外すと数えることを確かめる。spec は各パッケージの `spec/public`（`partnerships/recipients_spec.rb`・`partnerships/authentication_spec.rb`・`notifications/email_spec.rb`・`imports/runs_spec.rb`・`sales/item_prices_backfill_spec.rb`）と、受け手ごとの既存の spec に置く
    - 役割の制限は変えない。監査の行は、操作者のいない入口の書き込みを、いまのとおり `actor_type` の `system` で書く
11. `correctItemPrice` の理由の上限（OI-120）：200 文字にする（`graphql-schema.md`「mutation の一覧」の上限の表）。`Sales::ItemPrices.correct` が定数で持ち、超えたら何も書かずに `INVALID_INPUT`（`path` は `["reason"]`）を返す。理由を書く入口は `correctItemPrice` だけで、取り込みと `sales:backfill_item_prices` は訂正の理由を書かない。`spec/requests/item_prices_spec.rb` と `packs/sales/spec/public/sales/item_prices_spec.rb` に、200 文字ちょうどと 201 文字の example を足す

**完了条件**

最初に落とすテストは、`spec/scenarios/seeds_spec.rb` の「シードの後、受注側の `admin` で `supplier.dashboard` を読むと、状況ごとの件数が空でない」example である（シードが空の状態で、期待の不一致で落とす）。

```sh
bundle exec rspec spec/scenarios/seeds_spec.rb spec/scenarios/demo_world_spec.rb \
  packs/partnerships/spec/public/partnerships/onboarding_spec.rb packs/inventory/spec/public/inventory/stocks_spec.rb \
  spec/requests/dashboard_spec.rb spec/requests/item_prices_spec.rb spec/matrix/table_matrix_spec.rb spec/rubocop spec/contracts \
  packs/purchasing/spec packs/sales/spec packs/billing/spec packs/imports/spec packs/partnerships/spec packs/notifications/spec
bin/rails db:reset && bin/rails db:seed   # 2 回目の db:seed も通り、行が増えない
```

業務の今日（作るもの 9）で最初に落とすテストは、`dashboard_spec.rb` の日本時間の 0〜9 時の example（受注日が UTC の前日になり、期待の不一致で落ちる）である。作るもの 10 は、直す公開 API の単体の「設定を `on` にしても他社の行を数えない」example（所有の条件が無いので、他社の行を数えて落ちる）、作るもの 11 は `item_prices_spec.rb` の 201 文字の example（`INVALID_INPUT` の期待で落ちる）である。

- `spec/scenarios/seeds_spec.rb`：`DemoWorld.build(namespace: "", variant: :seed)` の後、両社の `admin` と `member` でログインして確かめる。受注側は `supplier.dashboard`・`supplier.salesOrders`・`supplier.invoices`・`supplier.imports` が値を返す。全権限の付与がある発注側は、`buyer.suppliers` とそのカタログ・出荷が値を返す。失効済みの発注側は、`buyer.suppliers` とカタログ・出荷が空になり（`graphql-schema.md`「発注側の視点」の経路 2）、自社の `buyer.purchaseOrders`・`buyer.receivedInvoices` は値を返す
- `spec/scenarios/demo_world_spec.rb`：同じ DB に `namespace` の違う 2 組を作れ、それぞれの 2 回目は行を増やさない。操作者を `member` に替えると、`admin` に限る段がどれも例外で止まる。`variant: :e2e` は、状況の enum の止まっていられる全値の行を持つ（OI-138）。作った後に、実行したジョブの `solid_queue_ready_executions` の行が残らず、取り込みの同時実行の鍵のセマフォ（`solid_queue_semaphores`）が上限の値（1）に戻り、同じテナントで次の取り込みを始めると、そのジョブが blocked にならずに ready になる。セマフォの行は返した後も残る（solid_queue 1.7.0 の `app/models/solid_queue/semaphore.rb` の `signal` は値を足すだけで、行を消さない）
- 置き場：2 つとも `spec/scenarios` に置く。どの層の置き場にも当たらないファイルは `bin/test-layers` が落とす

**範囲外**：公開の配置と訪問者ごとのデータ（M33 の著者判断 8）、性能の測定のための大量のデータ、サインアップの入口。

**実装する文書の節**：`graphql-schema.md`「役割による制限」「発注側の視点」、`data-model.md`「RLS」、`adr/005`（イベントの配送）、`guides/testing.md`「テストの層」

**文書に残すこと**：シードの流し方と `DemoWorld` を `README.md`「開発環境」に書く。`DemoWorld` が GraphQL を通らない入口として規則を評価することを、`graphql-schema.md`「役割による制限」の GraphQL を通らない入口の例に足す。作るもの 5 の `Partnerships::Onboarding.register` を、`tenants` へ追加する入口として `data-model.md`「RLS」に書く。

## M38 RLS の UPDATE のポリシーが隠す所有の条件を、単体で捕まえる

**目的**：操作者のいない入口の公開 API とイベントの受け手は、所有の条件を `Current.tenant_id` で明示する（`architecture/graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」）。単体は、共有の文脈「RLS の SELECT を開く」で他社の行を SELECT で見えるようにして、条件の抜けを確かめる。しかし、UPDATE と `SELECT ... FOR UPDATE` で行を引く箇所は、SELECT のポリシーに加えて UPDATE のポリシー（`owner_write`）の `USING` を満たす行しか対象にしないので、所有の条件を外しても他社の行が隠れ、単体が落ちない（IB-60）。共有の文脈を UPDATE にも広げ、この抜けを単体で捕まえる。業務の振る舞いは変えない。

**作るもの**

1. 試作と分かれ目：別名のテスト DB で、下の 2 が成り立つかを先に確かめる。サイクル 04 の改善の探索で、安全在庫の 1 か所は試作した（`plans/cycle-04/improvement.md`）。加えて、設定が `on` の間は、他社の行を自社の名義に書き換える UPDATE と `INSERT ... ON CONFLICT DO UPDATE` が通ること（改善の探索の Codex の指摘）を一時の表で確かめ、作るもの 3 の対照で捕まえられるかを証跡に書く。捕まえられなければ、判断の裏返る条件に従って止め、取りまとめ役に返す
2. `MatrixCrossRead` が、SELECT のポリシーに加えて、設定 `app.matrix_cross_read` が `on` のときだけ他社の行を UPDATE の対象に入れる UPDATE のポリシーを足す。名前は SELECT のポリシーと別にし、`FOR UPDATE` に限り、`WITH CHECK (false)` を明示する。`WITH CHECK` を書き落とすと PostgreSQL は `USING` を `WITH CHECK` に使うので、設定が `on` の間は他社の名義で書けてしまう。許可のポリシーの `WITH CHECK` は OR でつながるので、書いた後の行はいまの `owner_write` の `WITH CHECK`（自社の行）だけで判定される。`add!` は 2 つを同じトランザクションで足し、`remove!` と同名が残っていたときの失敗は 2 つに掛ける。足している間の `pg_policies` で、そのポリシーが `UPDATE` に限り、`with_check` が `false` であることを spec で確かめる。ポリシーの SQL は `spec/support` にだけ置く（M37 と同じ理由）
3. 確かめる箇所を、正本とコードから集める：操作者のいない入口の公開 API（`graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」の列挙）とイベントの受け手（配送表）のうち、UPDATE・`update_all`・`lock` で行を引く箇所を集める。箇所ごとに、共有の文脈で `cross_read!` を呼んでから他社の対象を渡す example を足す。example は、`cross_read!` で開いたまま同じ接続で他社の行を読み直し、他社の行が変わらないこと（所有の列を含む）を対照として確かめる。所有ロールの接続は別の接続なので、example のトランザクションの中で作った行と書き込みが見えない（`spec/rails_helper.rb` の `use_transactional_fixtures`）。設定が `on` の間は所有の移し替えが RLS を通るので、この対照が捕まえる。条件の付いた書き込み（`unless order.shipped_at` など）は、書く側の分岐を通る入力を選ぶ
4. 届かない形を `guides/testing.md` に書く：冪等キーにグローバルな一意索引がある受け手（他社に同じキーの行を作れない）、行ロックだけを取って書かない箇所（他社の行のロックが黙って通る）、DELETE（DELETE のポリシーは変えない）。どれも、箇所と、条件が二重の守りであることを書く

**判断**：UPDATE のポリシーを開くか、流した SQL を所有ロールの接続で流し直すか

- **既定の推奨**：UPDATE のポリシーを開く。M37・M32 で作った補助と共有の文脈をそのまま使い、箇所ごとの example は「`cross_read!` を呼んでから他社の対象を渡し、他社の行が変わらないことを確かめる」の 1 つで済む。テストの DB にだけ足すので、本番の規則は変わらない。設定が `on` の間に通る所有の移し替えは、example の対照で捕まえる
- **比べた案**：公開 API が流した SQL を `sql.active_record` で拾い、所有ロールの接続で SELECT に読み替えて流し直す案（M31 の `files_purge_owner_spec.rb` の形）は、書き込みのポリシーを変えないが、公開 API ごとに拾う文と読み替え方を書き、SQL の形が変わると検査が外れる。構文木で `Current.tenant_id` の条件を照らす案は、条件の書き方（補助のメソッド、関連をたどる絞り込み）が多く、外れが多い
- **裏返る条件**：作るもの 1 の試作で、所有の移し替えを対照で捕まえられない形が見つかる → SQL を流し直す案に移る
- **撤退コスト**：小さい。UPDATE のポリシーと足した example を外せば元に戻る。`structure.sql` は変えない。example が見つけた所有の条件の抜けの直しは、撤退しても残す

**完了条件**

```sh
bundle exec rspec spec/matrix spec/db/tenant_enforcement_spec.rb   # 0 failures
bundle exec rspec packs/notifications/spec/public/notifications/email_spec.rb packs/partnerships/spec/public/partnerships/authentication_spec.rb packs/inventory/spec/public/inventory/stocks_spec.rb packs/sales/spec/public/sales/item_prices_backfill_spec.rb packs/imports/spec/jobs/imports/purge_abandoned_files_job_spec.rb packs/*/spec/public/*/*_event_receiver_spec.rb   # 0 failures。作るもの 3 で集めた箇所の spec
```

2 つ目のコマンドは、操作者のいない入口の公開 API（`Notifications::Email.redeliver_failed`・`Partnerships::Authentication.revoke_sessions`・`Inventory::Stocks.set_safety_stock`・`Sales::ItemPrices.backfill`・`Imports::Files.purge_abandoned`）と、イベントの受け手の spec である。作るもの 3 で集めた箇所がほかの spec にあれば、そのパスをこのコマンドに足し、集めた一覧を証跡の「実装の記録」に書く。

期待の不一致で最初に落とすのは、`spec/matrix/cross_read_spec.rb` の、足している間の `pg_policies` の確かめ（UPDATE のポリシーが無い）である。ほかは、次の壊して落ちる記録を spec ごとに証跡の「実装の記録」に残す（`guides/dev-cycle.md`「テストから書く」）。

- 作るもの 3 で example を足した箇所から 1 つずつ所有の条件を外すと、その example が落ちる。外さなければ 0 failures
- UPDATE のポリシーから `WITH CHECK (false)` を外すと、`pg_policies` の確かめが落ちる。`remove!` が UPDATE のポリシーを外さないと、`tenant_enforcement_spec.rb` のポリシーの集合の確かめが落ちる
- 行列の 2 ファイルの時間を、変える前と後で証跡に書く（手元。流したコマンドと commit を添える。IB-50 の調べ直す条件を見る）

**範囲外**：操作者のいない入口の `Tenancy.require_tenant!` が `TenantRecord` の `default_scope` に隠れること（IB-59）、作るもの 4 の届かない形

**実装する文書の節**：`guides/testing.md`「行列テストとの分担」、`architecture/graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」

**文書に残すこと**：`guides/testing.md`「行列テストとの分担」の最後の段落（SELECT を開いても見えない所有の条件）を、UPDATE も開くことと届かない形に書き直す。共有の文脈の名前とコメント（`spec/support/cross_read.rb`）を、UPDATE も開くことに合わせる。

## M39 一覧の件数と並べ替え、列での絞り込み

**目的**：画面（M33）は一覧を 1 ページずつ読む（OI-07）。1 ページだけを画面で並べ替えると並びが嘘になり、読んだ行だけを数えると件数が嘘になるので、並べ替え・絞り込み・件数をサーバーで行う。この節は、すべての一覧に件数（`totalCount`）を、画面の一覧に並べ替え（`orderBy`）と、一覧の表の列で決まる絞り込み（`filter`）を足す。導出した状況での絞り込みは M40 で足す。あわせて、画面に要る入口を 2 つ足す（OI-12）。書き込みの振る舞いは変えない。

**作るもの**

1. 並べ替えの列と `id` の組でたどるページ：`Page.of`（`packs/platform`）に、並べ替えの列と向きを受け取る形を足す。並びは「列の値、`id`」の組にし、`id` を列と同じ向きに並べる。列の値が同じ行がページの境目をまたいでも、行が抜けも重なりもしない。値の無い行（希望納期の無い受注など）は、向きによらず最後に置く。カーソルは、並べ替えの列の名前・向き・列の値・`id` を持つ不透明な文字列にする。形の誤ったカーソルと、別の並べ替え（列か向きの違うもの）で作ったカーソルは、いまの形の誤ったカーソルと同じトップレベルのエラーにする。値の無い行を最後に置くので、カーソルの値が空の行の後ろは「値が空で `id` が後のもの」だけになり、値のある行の後ろの条件（値が後のもの、値が同じで `id` が後のもの、値が空のもの）と別に書く。`orderBy` を省いた一覧は、いまの並びとカーソルを変えない（`id` の降順。カタログは品目コードの昇順、取り込みの失敗行は行番号の昇順）。
2. 件数：コネクションの基底（`Types::BaseConnection`）に `totalCount: Int!` を足し、すべての一覧に持たせる。件数は、ページと同じ scope と絞り込みを掛けた relation の行の数で、`first`・`after` に左右されない。`Page` に件数を数えるブロックを持たせ、問い合わせが `totalCount` を選んだときだけ数える。`totalCount` だけを選び `nodes`・`edges`・`pageInfo` を選ばない問い合わせ（M33 のタブの件数）は、ページの行を読まず、値への写し（受注なら明細・引当・審査の読み込み）も流さない。公開 API は、件数のために scope と絞り込みを書き直さず、ページと同じ relation から数える。ページと件数を別々に絞ると、片方だけ scope が抜けても単体の spec では気づきにくい。
3. 並べ替えと絞り込みの引数：次の表の一覧に、`orderBy`（入力型 `<型>Order`）と `filter`（入力型 `<型>Filter`）を足す。`orderBy` は、一覧ごとの enum `<型>OrderField` の `field` と、`OrderDirection`（`ASC`・`DESC`）の `direction` を持ち、並べ替えの列は 1 つである。どちらの引数も省いてよく、省けば、いまの並びで、絞らずに返す。並べ替えの列は、一覧の表（同じパッケージの表）の列か、その列から計算する値に限る（判断）。

   | 一覧 | 並べ替えの列（`<型>OrderField`） | 絞り込み（`<型>Filter`） | 画面（M33） |
   |---|---|---|---|
   | `supplier.salesOrders` | `ORDER_NO`・`ORDER_DATE`・`DUE_DATE` | `customerTenantId: ID`、`orderDateFrom`・`orderDateTo: ISO8601Date` | 4・5 |
   | `buyer.purchaseOrders` | `ORDER_NO`・`ORDER_DATE`・`DESIRED_DELIVERY_ON` | `supplierTenantId: ID`、`orderDateFrom`・`orderDateTo: ISO8601Date` | 19 |
   | `supplier.shipmentRequests` | `DUE_DATE` | （状況は M40） | 9 |
   | `supplier.stocks` | `ON_HAND`・`ALLOCATED`・`AVAILABLE`（`on_hand - allocated`）・`SAFETY_STOCK` | `belowSafetyStock: Boolean` | 8 |
   | `supplier.stockMovements` | —（いまの `id` の降順） | `types: [StockMovementType!]`（`itemId` の引数はいまのまま） | 8 |
   | `supplier.items` | `CODE`・`NAME` | `keyword: String` | 10・7・20 |

   - 伝票番号は `PO-000001` の形の、桁をそろえた文字列である（`DocumentNumber`）。文字列の順が番号の順になるので、`ORDER_NO` は列をそのまま並べる。
   - 受注日の範囲は両端を含む。`orderDateFrom` が `orderDateTo` より後なら、空を返す（監査ログの `AuditLogFilter` と同じ）。
   - `belowSafetyStock` が真なら、ダッシュボードの `stocksBelowSafetyStock` と同じ条件（有効在庫が安全在庫を下回る）で絞る。条件を在庫のパッケージの 1 つの scope に置き、`Inventory::Stocks.below_safety_stock` と一覧の両方がそれを使う。集計と、そこから飛ぶ一覧が別の条件で絞ると、数が合わなくなる（M33 の流用元の規則「集計の数字と、そこから飛ぶ一覧は、同じ条件で絞る」）。偽か省いたときは絞らない。
   - `keyword` は、前後の空白を除いた文字列を、品目コードか品目名に含む品目に絞る。大文字と小文字を区別せず、`%`・`_` は文字として扱う。空の文字列は絞らない。100 文字を超える `keyword` は、引数の検証でトップレベルのエラーにする。
   - `types` の空の配列は 0 件を返し、省くか null なら絞らない。
   - 表に無い一覧（請求書・受領請求書・取り込み・取り込みの失敗行・品番の対応表・請求対象明細・請求書の明細・カタログ・監査ログ）は、件数だけを足す。画面で並べ替えと絞り込みの項目が決まっていないからである。
4. 入口を 2 つ足す（OI-12）：`supplier.item(id:)` は自社の品目を 1 件返し、見えない ID には `null` を返す（`architecture/graphql-schema.md`「ID と `node`」の 1 件を引くフィールド）。`viewer.tenant` は自社のテナントの `id` と `name` を返し、取引用コードを含めない（取引用コードは `viewer.partnerCode` が `admin` にだけ返す）。どちらも役割を問わない。
5. 行列テスト：コネクションを返すフィールドの行は、すべて問い合わせで `totalCount` を読む。`graphql_matrix_spec.rb` が、スキーマからコネクションを返すフィールドを集め、その行の問い合わせが `totalCount` を選ぶことを確かめる（規則の正本はスキーマ。`guides/dev-cycle.md`「テストから書く」）。表の 6 つの一覧には、並べ替えと絞り込みを両方渡す変種の行（`"SupplierView.salesOrders#filter"` の形）を足し、`MatrixWorld` の各ペルソナに、絞り込みに当たる行と当たらない行を持たせる。RLS を開いた 2 回目の比較（M37）が、件数・絞り込み・並びの scope の抜けを捕まえる。2 回目の比較は並びまで同じことを求めるので、`id` で決着しない並びは落ちる。`supplier.item`・`viewer.tenant` の行を、許す役割と期待値とともに足す。
6. S1 の入口の列挙：`SalesOrderFilter.customerTenantId`・`PurchaseOrderFilter.supplierTenantId` と `supplier.item(id:)` は、`spec/scenarios/tenant_boundary_spec.rb` の列挙に現れる。相手の伝票の ID とテナントの ID を渡して、一覧は空、1 件は `null` になる行を足す。同じ example で、自社の ID を渡せば自社の行が返ることを先に確かめる（`guides/testing.md`「S1 の入口の列挙」）。発注側の自社の発注は相手を受注側にしているので、`PurchaseOrderFilter.supplierTenantId` では相手のテナント ID が自社の行を返す対照になり、空になる ID には受注側の伝票の ID と取引の無いテナントの ID を渡す（OI-154）。
7. クエリ数の予算と複雑度：表の一覧を読む画面の問い合わせ（画面の問い合わせの一覧の `SupplierSalesOrders`・`BuyerPurchaseOrders`・`SupplierShipmentRequests`・`SupplierStocks`・`SupplierStockMovements`・`SupplierItems`）に、`totalCount` と、変数の `$orderBy`・`$filter` を足す。予算の表（`SCREENS`）には、並べ替えと絞り込みを渡す変数のメソッドを書く。絞り込みの値は、予算の spec が作る親がすべて当たるものにする。当たらないと 0 件どうしを比べ、N+1 を件数に出せない。件数は親の数によらず 1 つの問い合わせなので、親が 1 件と 20 件の SQL の件数は同じになる。`totalCount` だけを読む問い合わせの SQL の件数が、件数の 1 つ（とテナントの設定）だけであることを確かめる example も足す（作るもの 2）。`totalCount` はコネクションの要素の外にあるので、複雑度では `first` の倍にならない（`architecture/graphql-schema.md`「ページングと N+1」）。
8. 互換：足すのは、省いてよい引数・フィールド・新しい型だけなので、`bin/check-schema-compat` は非破壊の変更として通す。

テナントの境界：書き込みは足さない。足す読み取りは、どれもいまの公開 API の scope を掛けた relation に条件と並びを足すだけで、RLS と policy は変えない。絞り込みの ID（取引先のテナント ID）は自社の行の列と比べるだけで、相手の行を引かない。コンテキストの境界：在庫の安全在庫の条件は在庫のパッケージに、品目の `keyword` は受注のパッケージに置き、パッケージの依存の向きは変えない。

**判断**：並べ替えの列を、一覧の表の列に限るか

- **既定の推奨**：限る。流用元の画面は、取引先の名前、在庫の画面の品目のコードと名前、受注の金額の合計、状況でも並べる。取引先の名前と品目は別のコンテキストの表にあり、サーバーで並べるには、相手の表を結合するか、相手の公開 API から並びを受け取ることになり、公開 API が値を返す境界（`architecture/graphql-schema.md`「1 回のリクエストがたどる道」3）を越える。金額は明細の集計で、状況は M40 の式で並べられるが、どちらも画面のタブと絞り込みで足りる。画面は、並べられない列の見出しを並べ替えの対象にしない（M33）。
- **比べた案**：(a) 並べたい値を一覧の表に写す（受注に取引先の名前を持つ）。相手の変更を写しに追わせる受け手が要る。(b) ルートのリゾルバで全件を読んでから並べる。件数が増えても並びが正しいことを求めた作者の判断（OI-07）と、1 ページずつ読む形に反する。
- **裏返る条件**：作者が、表に無い値（取引先の名前、在庫の品目コード）での並べ替えか、在庫の画面での品目の検索を求める（OI-144 で作者に確かめる） → (a) の写しの列を足す。
- **撤退コスト**：小。足すだけの変更で、並べ替えの enum に値を足しても互換の検査は通る。

**完了条件**

```sh
bundle exec rspec packs/platform/spec/models/page_spec.rb packs/sales/spec/public/sales/sales_orders_spec.rb packs/sales/spec/public/sales/catalog_spec.rb packs/purchasing/spec/public/purchasing/purchase_orders_spec.rb packs/fulfillment/spec/public/fulfillment/shipment_requests_spec.rb packs/inventory/spec/public/inventory/stocks_spec.rb   # 0 failures
bundle exec rspec spec/matrix spec/scenarios/tenant_boundary_spec.rb spec/graphql/query_budget_spec.rb spec/graphql/query_complexity_spec.rb spec/platform/metrics_subscriber_spec.rb   # 0 failures
bin/check-schema-compat   # 破壊的な変更 0 件
```

期待の不一致で最初に落とすのは、`page_spec.rb` の、並べ替えの列の値が同じ 3 行と値の無い 2 行をページの境目にまたがせて、`ASC` と `DESC` の両方で読み、行が抜けも重なりもしないことを確かめる example と、行列の「コネクションを返すフィールドの行が `totalCount` を読む」の確かめである。ほかは、次の壊して落ちる記録を spec ごとに証跡の「実装の記録」に残す。

- 件数を数える relation から scope を外すと、行列の 2 回目の比較が落ちる。並べ替えから `id` を外すか、値の無い行の後ろの条件を外すと、`page_spec.rb` の境目の example が落ちる。カーソルから向きを外すと、`page_spec.rb` の、向きだけを変えたカーソルを拒む example が落ちる
- `totalCount` だけの問い合わせでページを読むと、`query_budget_spec.rb` の、件数だけを読む問い合わせの SQL の件数を確かめる example が落ちる
- `belowSafetyStock` の一覧と `below_safety_stock` の条件を別々に書き、片方の不等号を変えると、在庫の公開 API の spec の、同じ世界で両方の件数を比べる example が落ちる
- `keyword` の `%` を文字として扱わないと、`catalog_spec.rb` の `%` を含む `keyword` の example が落ちる

**範囲外**：状況での絞り込み（M40）、一覧の表に無い値での並べ替え（判断）、前のページへ辿る引数（`last`・`before`）。

**実装する文書の節**：`architecture/graphql-schema.md`「ページングと N+1」・「読み取りの一覧」・「ID と `node`」、`guides/testing.md`「S1 の入口の列挙」・「行列テストとの分担」

**文書に残すこと**：`architecture/graphql-schema.md`「ページングと N+1」に、一覧が持つ引数（並べ替え・絞り込み・件数）と、カーソルの中身と、値の無い行の置き場所を書く。同じ節の「件数の総数（`totalCount`）は返さない」と、画面の検索の引数を後で足すという文を消す。SDL の受注側と発注側の視点に、足した引数・入力型・enum・`totalCount`・`supplier.item(id:)`・`viewer.tenant` を書く。

## M40 状況での絞り込み

**目的**：受注・発注・出荷依頼の画面は、状況のタブで一覧を分け、タブごとの件数を出す（M33 の画面 4・5・9・19）。状況は保存せず、公開 API が時刻列と子の行から導出する（`architecture/data-model.md`「状態は保存せず、時刻列から導出する」）ので、いまは行を読んだ後でしか分からない。この節は、状況での絞り込みと件数を、一覧を読む SQL の中で行えるようにする（OI-07）。ダッシュボードの状況ごとの件数も同じ導出で数え、ダッシュボードの数と、そこから飛ぶ一覧の件数を一致させる。書き込みの振る舞いは変えない。

**作るもの**

1. 状況の導出を SQL の式にする：`Sales::SalesOrderStatus`・`Purchasing::PurchaseOrderStatus`・`Fulfillment::ShipmentRequestStatus` が、導出表と同じ優先順の `CASE` 式を返す。公開 API の一覧・1 件・件数は、行と一緒にこの式の値を読み、Ruby の `derive` を消す。受注の取消の可否（`Sales::OrderCancelling`）も、ロックした受注の状況をこの式で読む。導出を 1 か所にし、表示・絞り込み・件数が別々に導出しないためである（判断）。各パッケージの式が読む表は次のとおりである。

   | 状況 | 式が読むもの | 別のコンテキストの値 |
   |---|---|---|
   | 受注 | 受注の時刻列、受注明細の照合の状態、受注明細ごとの有効な引当数量 | 引当数量は在庫の表にある。在庫の公開 API `Inventory::Allocation.active_quantities_sql(actor)` が、操作者の scope を掛けた「受注明細 ID と有効な引当数量」を返す副問い合わせを、SQL の文字列と列の名前だけを持つ値（`SqlSubquery`、`packs/platform`）で返し、受注の式がそれを結ぶ。条件は、いまの `Inventory::Allocation.quantities_for` と同じ（解放済みを除く）にする（判断「別のコンテキストの値をどう渡すか」） |
   | 発注 | 発注の時刻列、入荷と検収の有無 | 無い（購買の表だけ） |
   | 出荷依頼 | 出荷依頼の時刻列、有効な出荷指示・出荷実績・解除されていない出荷停止の有無 | 無い（出荷の表だけ） |

2. 絞り込み：`SalesOrderFilter`・`PurchaseOrderFilter` に `statuses: [<状況の enum>!]` を足し、出荷依頼に `ShipmentRequestFilter`（`statuses: [ShipmentRequestStatus!]`）を足す。省くか null なら絞らず、空の配列なら 0 件を返す。M39 の列の絞り込みと同時に渡せば、両方に当たる行に絞る。件数（`totalCount`）は同じ条件で数える。取消の依頼中・審査中（`cancellationPending`・`cancellationReviewPending`）は状況ではないので、絞り込みに入れない（`architecture/graphql-schema.md`「状況の enum」）。
3. ダッシュボードの件数：`Sales::SalesOrders.count_by_status` を、同じ式で `GROUP BY` して数える形にする。いまは全件を読んで Ruby で数えている。0 件の状況も返す形は変えない。ダッシュボードの出荷期限（`Fulfillment::ShipmentRequests.due_within`）の「出荷も取消もしていない」も、出荷依頼の式で出荷待ち・出荷指示済・出荷停止中に絞る形にする（OI-159）。
4. 行列テスト：M39 で足した 3 つの一覧の変種の行に、`statuses` を足す。出荷依頼の行は並べ替えだけの `#orderBy` なので、`#filter` に変えて並べ替えと状況を渡す（OI-158）。世界には、絞る状況に当たる行と当たらない行を持たせる。引当数量の副問い合わせから scope を外しても、行列の 2 回目の比較では捕まらない。他社の引当は他社の受注明細を指し、自社の受注明細には結ばれないので、RLS を開いて他社の引当が見えても状況は変わらないからである。捕まえるには他社の名義で自社の受注明細を指す引当が要るが、公開 API とイベントでは作れない。そこで、`allocation_spec.rb` に、共有の文脈「RLS の SELECT と UPDATE を開く」（M38）で他社の引当を見えるようにしてから副問い合わせを流し、他社の行が入らないことを確かめる example を足す。同じ example で、scope を掛けなければ他社の行が入ることを先に確かめる（対照）（`guides/testing.md`「行列テストとの分担」）。
5. クエリ数の予算：受注・発注・出荷依頼の画面の問い合わせに渡す `$filter` に、予算の spec が作る親がすべて当たる状況の集まりを足す。

テナントの境界：書き込みは足さない。式は、公開 API の scope を掛けた relation に列を足すだけで、RLS と policy は変えない。在庫の副問い合わせは在庫の policy の scope を掛けた後に SQL の文字列にするので、受け取る受注のパッケージは条件を外せない。所有の条件を RLS に任せない（`architecture/graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」）。式が読む子の行（受注明細・入荷・検収・出荷指示・出荷実績）は、所有テナントと親の組の外部キーで親と同じテナントに限られる。外部キーの無い出荷停止は、式が所有テナントを出荷依頼にそろえる（OI-160）。コンテキストの境界：受注はすでに在庫の公開 API（`Inventory::Allocation`）に依存しているので、依存の向きは変わらない。受注のパッケージは在庫のモデルも relation も受け取らず、在庫の表の名前と列を書かない（列の名前は値が持つ）。

**判断**：別のコンテキストの値を、SQL の中でどう渡すか

- **既定の推奨**：在庫の公開 API が、scope を掛けた relation を SQL の文字列にし、列の名前と一緒に値（`SqlSubquery`）で返す。受け取る側は、文字列を副問い合わせとして結ぶだけで、条件を足すことも外すこともできない。結ぶ側は文字列を `Arel.sql` で包み、Brakeman（共通の完了条件）が SQL の埋め込みの警告を出したら、`config/brakeman.ignore` に指紋と、値が scope を掛けた公開 API の戻り値だけであるという理由を書く。モデルと書き込みの入口は在庫のパッケージの外に出ない（`adr/002`「AR モデルは公開しない」）。
- **比べた案**：(a) relation をそのまま返す。受け取る側が `unscope`・`rewhere`・`update_all` を呼べ、在庫の scope と書き込みの入口が境界を越える。packwerk は定数の参照しか見ないので、これを止められない。(b) 受注明細 ID の配列を受け取り、引当数量を返す（いまの `quantities_for`）。行を読んだ後でしか状況が決まらず、SQL の中で絞り込めない。
- **裏返る条件**：SQL の文字列にした副問い合わせを、受け取る側で結べない（PostgreSQL の実行計画で、一覧の SQL が遅くなりクエリ数の予算の spec の時間を大きく延ばすなど） → 引当の有無を受注の側に写す列を足す（受け手で写しを保つ）。
- **撤退コスト**：小。値と公開 API を 1 つ消し、受注の式を (b) の読み方に戻す。

**判断**：状況の導出を SQL の式 1 つにするか、Ruby の導出を残して SQL の条件を足すか

- **既定の推奨**：SQL の式 1 つにし、Ruby の `derive` を消す。表示・絞り込み・件数・取消の可否が同じ式を読むので、導出表を変えたときに直す箇所が 1 つで、ダッシュボードの数と一覧の件数が食い違わない。
- **比べた案**：Ruby の `derive` を残し、状況ごとの SQL の条件を足して、両者の一致を spec で確かめる。いまの導出のコードを変えずに済むが、同じ意味を 2 か所に持ち、一致の spec は世界にある状況の組み合わせしか確かめない。
- **裏返る条件**：導出表のどれかの行を、1 つの SQL の式で書けないか、式を足した一覧がクエリ数の予算を超える → 比べた案に移る。
- **撤退コスト**：中。3 つの状況のモジュールに `derive` を戻し、件数と取消の可否を元の読み方に戻す。絞り込みの引数は、比べた案の SQL の条件で残せる。

**完了条件**

```sh
bundle exec rspec packs/sales/spec/models/sales/sales_order_status_spec.rb packs/purchasing/spec/models/purchasing/purchase_order_status_spec.rb packs/fulfillment/spec/models/fulfillment/shipment_request_status_spec.rb   # 0 failures
bundle exec rspec packs/sales/spec/public/sales/sales_orders_spec.rb packs/sales/spec/public/sales/order_cancellation_spec.rb packs/purchasing/spec/public/purchasing/purchase_orders_spec.rb packs/fulfillment/spec/public/fulfillment/shipment_requests_spec.rb packs/inventory/spec/public/inventory/allocation_spec.rb   # 0 failures
bundle exec rspec spec/matrix spec/graphql/query_budget_spec.rb spec/requests/dashboard_spec.rb   # 0 failures
```

`allocation_spec.rb` の、RLS を開いても副問い合わせに他社の引当が入らないことを確かめる example も、このコマンドに含まれる。期待の不一致で最初に落とすのは、3 つの状況の spec を、導出表の行ごとに 1 件ずつ作って `statuses` で絞り、その 1 件だけが返ることを確かめる形に書き直した example である（いまは `derive` に値を渡して確かめている）。ほかは、次の壊して落ちる記録を spec ごとに証跡の「実装の記録」に残す。

- 式の優先順を 2 つ入れ替えると、両方に当たる行（検収済で出荷済の受注など）の example が落ちる。取消済と出荷済のように DB の CHECK 制約で同時に持てない組は作れないので、組まない
- 引当数量の副問い合わせから解放済みを除く条件を外すと、受注の状況の spec の、引当を解放した受注の example が落ちる。副問い合わせから scope を外すと、`allocation_spec.rb` の RLS を開いた example が落ちる
- `count_by_status` を別の条件で数えると、`sales_orders_spec.rb` の、状況ごとの件数と `statuses` で絞った一覧の件数を比べる example が落ちる

**範囲外**：状況での並べ替え（M39 の判断）、取消の依頼中・審査中での絞り込み。

**実装する文書の節**：`architecture/data-model.md`「状態は保存せず、時刻列から導出する」、`architecture/graphql-schema.md`「状況の enum」・「ページングと N+1」

**文書に残すこと**：`architecture/data-model.md`「状態は保存せず、時刻列から導出する」に、導出を公開 API の SQL の式で行い、表示・絞り込み・件数が同じ式を読むことを書く。`architecture/graphql-schema.md`「状況の enum」に、状況の絞り込みの引数と、重ねて示すフィールドを絞り込みに入れないことを書く。同じ文書の「1 回のリクエストがたどる道」3 に、公開 API が返す値に、scope を掛けた後に文字列にした副問い合わせ（`SqlSubquery`）があり、受け取る側は条件を足さずに結ぶだけであることを書く。2 つの判断の比べた案と裏返る条件は ADR（`adr/010`）に書く。複数のコンテキストにまたがり、案を比べたからである（`guides/dev-cycle.md`「書く前の振り分け」）。

## M33 フロントエンド

**目的**：姉妹プロジェクト factory-ops-demo の `frontend/`（以下、流用元）の Next.js を写し、画面部品をそのまま使い、データ取得層を REST から GraphQL へ書き換え、発注側の画面を足す。読み手が、受注側と発注側の両方の画面で、取引関係・失効・取消・検収・請求が動くのを見られるようにする。画面が一覧を 1 ページずつ読むための並べ替え・絞り込み・件数は M39・M40 で API に足してあり、公開の配置は M41 で作る。

本節の用語は次のとおりである。**受注側**は GraphQL の `supplier` の視点（自社が受けた受注・在庫・出荷・請求を扱う）、**発注側**は `buyer` の視点（自社の発注と、相手を読む 3 経路を扱う）を指す。**画面**は Next のルート 1 つを指す。**入口**は GraphQL のルートのフィールド `viewer`・`buyer`・`supplier` を指す（`graphql-schema.md`「視点ごとに型を分ける」）。**画面の問い合わせ**は、画面が送る query と mutation の文書を指す（M17 の同名の一覧と同じもの）。

担当者は、次の順に決めて作る。まず、流用元を本リポジトリのどこへ写すかを決める（置き場所）。次に、写した画面と足す画面が、どの入口を呼び、それがどのマイルストーンでそろうかを確かめる（画面の一覧）。そのうえで、画面の部品はそのままに、REST の呼び出しを GraphQL の呼び出しに替える（データ取得層）。最後に、それを流用元の E2E の規則と本リポジトリの CI で守る（テストとゲート）。各段の「判断」は担当者が既定のとおりに進めてよいもので、作者が決めたことは末尾の「著者判断」にある（OI-06〜OI-14）。

**作るもの 1：置き場所**

- 流用元の main（`958de71`）の `frontend/` を、本リポジトリの `frontend/` に写す。git の履歴は持ち込まず、写した commit を commit メッセージに書く。
- 写さないもの：Cloudflare への配置（配置は M41 の k3s で行う。`wrangler.jsonc`・`open-next.config.ts`・`@opennextjs/cloudflare`・`wrangler`）、訪問者ごとのデモの開始・サンプル表示・混雑の通知（`lib/start-demo.ts`・`demo-session.ts`・`demo-state.ts`・`sample.ts`・`sample-data.json`・`components/demo-notice.tsx` と、それを分岐に使う箇所）、REST のスタブ（`e2e/stub-api.mjs`）と Go の API を起こす `e2e/start-api.sh`。
- Ruby の検査から外す：`.rubocop.yml` の `AllCops.Exclude`、`packwerk.yml` の `exclude`、`.dockerignore` に `frontend/` を足す。`.github/dependabot.yml` に `frontend/` の npm を足す。
- コードのコメント：写す担当者は、流用元の仕様・タスク・台帳の番号を指すコメント（`T-34`・`仕様 §7`・`正本 N-5`・流用元の台帳の `OI-NN` の類）を、いまの振る舞いと理由に書き直すか消す。`guides/comments.md` の対象に `frontend/` を足し、`frontend/scripts/check-comments.mjs` が、これらの番号とマイルストーンの番号を含むコメントを落とす。`npm run lint` から呼ぶ。

**判断**：流用元をどこに置くか

- **既定の推奨**：本リポジトリの `frontend/` に写す。`schema.graphql` と画面の問い合わせが同じ commit で変わり、同じ CI で型検査される。非推奨を経ないスキーマの変更（M20）も、フロントエンドの型検査として同じ PR で落ちる。
- **裏返る条件**：流用元と本デモの両方で、画面部品をこれからも育てる → 部品を npm のパッケージに切り出し、両方から読む。
- **撤退コスト**：中。`frontend/` を別のリポジトリへ移すと、`schema.graphql` を取りに行く手順と、画面の問い合わせの一致を確かめる検査が要る。

**作るもの 2：画面の一覧**

画面の URL は視点で分け、受注側を `/supplier/...`、発注側を `/buyer/...` に置く。サイドバーは「受注側」「発注側」の 2 つのグループを持つ（著者判断 4）。表の「作るマイルストーン」は、画面が呼ぶ入口のフィールドと mutation を作るマイルストーンである。一覧の並べ替え・絞り込み・件数の引数は、M39（列）と M40（状況）で足す。M15 以降のマイルストーンに依存する画面には ※ を付けた。

| | 画面 | 視点 | 流用元の画面 | 呼ぶ入口のフィールドと mutation | 作るマイルストーン |
|---|---|---|---|---|---|
| 1 | `/` ログイン | 共通 | `/`（デモを開始） | `POST /session`・`DELETE /session`（`SessionsController`）、`viewer`（著者判断 3） | M4・M8 |
| 2 | `/settings` 自社の情報 | 共通 | —（新規） | `viewer`（取引用コード `partnerCode` は `admin` だけ） | M8 |
| 3 ※ | `/audit-logs` 監査ログ | 共通 | —（新規） | `viewer.auditLogs`（`admin` だけ）。シードと E2E の世界は監査の行を書かないので、作った直後はイベントの受信の行だけが並ぶ（OI-141） | M19 |
| 4 ※ | `/supplier/dashboard` ダッシュボード | 受注側 | `/dashboard` | `supplier.dashboard`、かんばんは状況ごとに `supplier.salesOrders(filter: { statuses: [<状況>] })` を別名で並べる（列ごとに `first: 10` と `totalCount`）、カードの操作は `allocateSalesOrder`・`createShippingInstruction`・`postShipment` | M26・M10・M12・M13・M40 |
| 5 | `/supplier/sales-orders` 受注一覧 | 受注側 | `/orders` | `supplier.salesOrders`（`orderBy`、取引先と受注日の範囲の `filter`、タブの状況の `filter.statuses`、タブごとの `totalCount`） | M10・M39・M40（状況の「検収済」は M23、取消審査中の印は M21） |
| 6 ※ | `/supplier/sales-orders/[id]` 受注詳細 | 受注側 | `/orders/[id]` | `supplier.salesOrder`、`allocateSalesOrder`・`createShippingInstruction`・`cancelSalesOrder`・`approveCancellationReview`・`rejectCancellationReview` | M10・M12・M13・M21・M22 |
| 7 | `/supplier/part-mappings` 品番の対応表 | 受注側 | —（新規） | `supplier.partMappings`・`registerPartMapping`、照合待ちの受注は `supplier.salesOrders`、品目の候補は `supplier.items` | M11 |
| 8 | `/supplier/stocks` 在庫と移動履歴 | 受注側 | `/stocks` | `supplier.stocks`（`orderBy`、`filter.belowSafetyStock`）・`supplier.stockMovements`（`filter.types`）・`adjustStock` | M12・M39 |
| 9 | `/supplier/shipment-requests` 出荷依頼 | 受注側 | `/shipping-instructions` | `supplier.shipmentRequests`（`orderBy`、`filter.statuses`）・`createShippingInstruction`・`cancelShippingInstruction`・`postShipment` | M13・M39・M40（状況の「出荷停止中」は M21） |
| 10 | `/supplier/items` 品目 | 受注側 | `/items` | `supplier.items`（`orderBy`、`filter.keyword`）・`saveItem`・`setItemPublished` | M9・M39 |
| 11 ※ | `/supplier/items/[id]` 品目の単価の履歴と改定 | 受注側 | —（新規） | `supplier.item(id:)`（著者判断 6）・`Item.prices(asOf:)`・`scheduleItemPrice`・`correctItemPrice` | M27・M39 |
| 12 | `/supplier/partnerships` 取引関係 | 受注側 | `/customers` | `supplier.partnerships`・`establishPartnership`・`revokePartnership`・`grantPermission`・`withdrawPermission`（変更は `admin` だけ） | M8 |
| 13 ※ | `/supplier/billing` 請求の締め | 受注側 | —（新規） | `supplier.billingTerms`・`setBillingTerm`・`supplier.billableItems`・`closeBillingPeriod` | M24 |
| 14 ※ | `/supplier/invoices` 請求書一覧 | 受注側 | —（新規） | `supplier.invoices` | M24 |
| 15 ※ | `/supplier/invoices/[id]` 請求書詳細 | 受注側 | —（新規） | `supplier.invoice`・`Invoice.items`・`BillableItem.priceExplanation`・`discardDraftInvoice`・`issueInvoice` | M24・M25・M27 |
| 16 ※ | `/supplier/imports` 取り込みの一覧と開始 | 受注側 | —（新規） | `POST /imports/files`・`startImport`・`supplier.imports` | M29 |
| 17 ※ | `/supplier/imports/[id]` 取り込みの進み具合 | 受注側 | —（新規） | `supplier.import`・`Import.rowErrors`。進行中は数秒ごとに `router.refresh()` で読み直す | M29 |
| 18 | `/buyer/suppliers` 取引先とカタログ | 発注側 | —（新規） | `buyer.suppliers`（取引先の一覧。カタログを入れ子にしない）、選んだ 1 社のカタログは `buyer.supplier(supplierTenantId:)` の `SupplierPartnership.catalog`（画面の問い合わせ `BuyerSupplierCatalog`、OI-17） | M8・M9 |
| 19 | `/buyer/purchase-orders` 発注一覧 | 発注側 | `/orders` | `buyer.purchaseOrders`（`orderBy`、取引先と発注日の範囲の `filter`、タブの状況の `filter.statuses`、タブごとの `totalCount`）。入荷を待つ発注は「入荷予定」のタブ（`statuses: [INBOUND]`）で見る（著者判断 7） | M10・M39・M40（状況の「入荷予定」は M14、「検収済」は M23、取消は M21・M22） |
| 20 | `/buyer/purchase-orders/new` 発注登録 | 発注側 | `/orders/new` | `buyer.suppliers`（`place_orders` の付与のある相手）、選んだ相手のカタログは `buyer.supplier(supplierTenantId:)` の `SupplierPartnership.catalog`（参照に並べる。画面 18 と同じ問い合わせ）・`placePurchaseOrder`（操作名 `PlacePurchaseOrder`、M30 の登録の表）。品番は自社品番を入力する | M8・M9・M10 |
| 21 ※ | `/buyer/purchase-orders/[id]` 発注詳細（入荷・検収・取消依頼） | 発注側 | `/orders/[id]` | `buyer.purchaseOrder`（`inboundShipments`・`supplierShipments`・`cancellationRequests`）・`inspectInboundShipment`・`requestPurchaseOrderCancellation` | M10・M14・M21・M23 |
| 22 ※ | `/buyer/received-invoices` 受領請求書一覧 | 発注側 | —（新規） | `buyer.receivedInvoices` | M25 |
| 23 ※ | `/buyer/received-invoices/[id]` 受領請求書詳細 | 発注側 | —（新規） | `buyer.receivedInvoice` | M25 |

`admin` に限る操作（`graphql-schema.md`「役割による制限」の表）のボタンは、`viewer.role` が `admin` のときだけ出す。画面 2・3・12 のほか、画面 6 の取消と審査、11 の単価の改定と訂正、13 と 15 の請求の操作、21 の検収と取消依頼が当たる。画面 16 の取り込みの開始は種類で許す役割が変わるので、種類 `items` の選択肢だけを `admin` に出し、`stocks` は役割を問わず出す。

流用元にあって API に無い操作は、画面から外す。受注側による受注の登録（受注は発注からイベントで作られる）、明細ごとの引当と引当の解除（`allocateSalesOrder` は受注の単位で引き当てる）、品目と得意先の削除、得意先の住所と担当者がこれに当たる。流用元の品目の安全在庫は、在庫の値（`Stock.safetyStock`）として在庫の画面に出す。

受注の状況は、流用元の 6 つから `SalesOrderStatus` の 7 つに替わる。ダッシュボードのかんばんの列は 7 つにし、流用元の「出荷指示済」の列は無くなる。出荷指示の有無はカードの `shipmentRequest.status` が `INSTRUCTED` であることで示し、「出荷実績計上」のボタンを出す。取消審査中と取消依頼中は、状況のバッジに重ねる印で示す（`graphql-schema.md`「状況の enum」）。流用元に無い状況のバッジの色は、著者判断 2 による。

**作るもの 3：データ取得層**

流用元は、サーバーコンポーネントで読み、server action で書き、どちらも Next のサーバーから API を呼ぶ。この形を保ち、呼び先だけを Rails の GraphQL に替える。

- **呼び出し口**：`lib/graphql/request.ts` の 1 か所だけが Rails を呼ぶ。流用元の `lib/api-client.ts`・`api.ts`・`api-types.ts` と、`lib/*-actions.ts` の REST の呼び出しを、これに置き換える。`fetch` は `cache: "no-store"` で呼び、Next のデータのキャッシュ（`"use cache"`・`unstable_cache`・`fetch` の `next.revalidate`）は使わない。`"use cache"` と `unstable_cache` は関数の引数を鍵にし、セッションを鍵に含めないので、あるテナントへの応答を別のテナントに返すからである。`fetch` のキャッシュは鍵に要求のヘッダを含めるが、書き込みの後の画面に古い値を出す（OI-166）。ESLint の `no-restricted-syntax` と `no-restricted-imports` で、これらを書くと落ちるようにする。
- **型の生成**：`@graphql-codegen/cli` が、根の `schema.graphql` と `frontend/graphql/**/*.graphql` から、操作ごとの `TypedDocumentNode` を `lib/graphql/generated.ts` に書き出す。生成物は commit し、CI で生成し直して差分が無いことを確かめる（`npm run codegen:check`）。カスタムのスカラー `BigInt`・`ISO8601Date`・`ISO8601DateTime` は `string` に写す。金額は `BigInt` で足し引きし、`Number` に直さない（`lib/format.ts`）。流用元が API の応答から読んでいた業務日付は、Next では決めず、API が返す業務の今日（`supplier.dashboard.businessDate`）を使う。業務の今日を決める場所が Rails と Next の 2 か所になると、OI-117 で決めた形と画面の今日がずれるからである。API に無い画面で要るときは、著者判断 6 と同じく足すだけの変更として入口に足す。サイドバーの自社の名前は `viewer.tenant`（M39）から出す。
- **画面の問い合わせ**：`frontend/graphql/<視点>/<操作名>.graphql` に 1 ファイル 1 つで置き、断片（fragment）はそのファイルの中でだけ使う。
- **一覧の読み方**（著者判断 1）：一覧の画面は 1 ページ（`first: 20`）ずつ読む。流用元が URL に持つ並べ替え（`sort`・`dir`）・タブ・絞り込みの値を、`orderBy` と `filter`（M39・M40）に写し、次のページは `pageInfo.endCursor` を `after` に入れた URL で開く。API は前のページへ辿らないので（`graphql-schema.md`「ページングと N+1」）、前へはブラウザの戻る操作と「最初のページ」へのリンクで戻る。一覧の件数とタブごとの件数は、同じ問い合わせの中で、タブの `filter` を渡した一覧を別名で並べ、`totalCount` だけを読む。流用元の並べ替え・絞り込み・タブの件数の純関数（`lib/sort.ts` の `sortRows`、`lib/order-list.ts` の `buildOrderList`、`lib/sample.ts` の `filterByQuery` など）は写さず、URL の値を変数に写す関数に置き換える。同じ意味を画面とサーバーの 2 か所に持たないためである。API で並べられない列（取引先の名前・金額の合計・状況・在庫の品目のコードと名前。M39 の判断）の見出しは、並べ替えの対象にしない。作者が OI-144 で既定を変えたら、足した並べ替えの列の見出しを対象に戻す。在庫の画面には品目の検索の欄を置かず、安全在庫を下回るものだけを出す切り替え（`filter.belowSafetyStock`）を置く
- **かんばんの列**：ダッシュボードのかんばんは、状況ごとに `supplier.salesOrders(filter: { statuses: [<状況>] }, first: 10)` を別名で 7 つ並べ、列の見出しに `totalCount` を出し、列の下に、その状況で絞った受注一覧へのリンクを置く。列の件数は変数にせず `first: 10` と書く。複雑度の spec は変数の `first` を上限の 100 にして計るので、7 つの列を変数で読むと上限を超える。かんばんは別の画面の問い合わせ `SupplierKanban` にし、クエリ数の予算の表に、2 つ目からの列を `more_lists` で書く。いまの予算の spec は、どの一覧も返す件数が親の件数（1 件と 20 件）と等しいことを求めるので、表の一覧の行に 1 ページの上限（`page_size: 10`）を持てるようにし、返す件数を親の件数とその上限の小さい方と比べる形に広げる。予算の世界は、1 回の準備で 7 つの状況の受注を 1 件ずつ足す（取消済・検収済・出荷済を含む）
- **認証**：ログインの server action が、Rails の `POST /session` に JSON で資格情報を送り、応答の `Set-Cookie` にあるセッションの Cookie（`_factory_ops_session`）を、同じ属性（`HttpOnly`・`SameSite=Lax`・本番は `Secure`・期限）で `cookies().set` に写す。`request.ts` は、ブラウザから届いた Cookie のうちセッションの Cookie だけを Rails へ送る。ログアウトの server action は `DELETE /session` を呼び、Cookie を消す。Rails が応答のたびに延ばす期限の扱いは、著者判断 5 による。
- **`Origin` と CSRF**：ブラウザが見るオリジンはフロントエンドの 1 つだけにし、Rails の CORS は開けない（`guides/config.md`「CSRF を防ぐ前提：CORS を開けない」）。ブラウザからの書き込みは server action を通り、Next が `Origin` と `Host` の一致を確かめる。Next のサーバーは Rails へ `Content-Type: application/json` で送るので、`ApplicationController` の制限をそのまま通る。例外は取り込みのファイル（M29 の `POST /imports/files`）で、`next.config.mjs` の `rewrites` で同じオリジンの下に出し、ブラウザから `multipart/form-data` で送る。Rails は、ブラウザの `Origin` を、許可したオリジン（フロントエンドのオリジン）と比べる。
- **エラー**：`request.ts` が応答を次の表のとおりに分け、画面は分けた結果だけを見る。流用元の `ApiResult` の `code` の一覧は、この分け方に置き換える。ユーザーエラーの `message` は API の文言をそのまま出し、言い換えるのは次にすることを書き足すときだけにする（流用元の `handbook/README.md`「同じ意味を2箇所に実装しない」）。

  | 応答 | 画面の扱い |
  |---|---|
  | HTTP 401 | セッションの Cookie を消し、ログインの画面へ移す |
  | 接続できない・5xx・タイムアウト | 流用元の「API に届かない」表示（`error-notice`・`list-error`）を出す |
  | ID で引く入口（`supplier.salesOrder(id:)` など）の `null`、mutation の `NOT_FOUND` | どちらも流用元の見つからない画面（`not-found-message`）にする。無いのか見えないのかを言い分けない。例外は `establishPartnership` の取引用コードの `NOT_FOUND` で、入れた値の誤りなので、入力欄の下に出す（OI-162） |
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

- **既定の推奨**：`frontend/graphql/` を正本にする。M17 の `spec/fixtures/graphql/screens/` を消し、クエリ数の予算（M17）・複雑度のテスト（M26）・操作名の登録の一致のテスト（M30）が `frontend/graphql/` を読むように替える。画面が実際に送る問い合わせと、検査する問い合わせが 1 つになる。`frontend/graphql/` には mutation の文書と詳細の問い合わせも入るので、クエリ数の予算と複雑度のテストは query の文書だけを対象にし、予算の表（`SCREENS`）に、query の文書のすべて（一覧と詳細）の行を足す。予算の spec は、query の文書と表の行の一致を確かめるからである。操作名の登録の一致のテストは、query を登録の表の `queries` と、mutation を `mutations` と照らす。
- **裏返る条件**：`frontend/` を別のリポジトリに置く → `spec/fixtures/graphql/screens/` を残し、フロントエンドの CI で両者の一致を確かめる。
- **撤退コスト**：中。3 つのテストの読み先を替え、予算と複雑度のテストに query だけを選ぶ条件を足し、予算の表に画面の query の文書の行を足す。

**作るもの 4：テストとゲート**

流用元の E2E は、Go の API に当てる live と、REST のスタブに当てる stub の 2 系統である。本デモは、Rails に当てる 1 系統にする。stub が作っていた「API に届かない」状態は、届かない URL を向いた Next のサーバーをもう 1 つ立てて作る。

- **E2E の世界**：Playwright の `webServer` が、`bin/rails server`（`RAILS_ENV=test`、DB は `TEST_DATABASE=factory_ops_e2e`）・`bin/jobs`（イベントを流す）・`next start` を起こす。Rails の `webServer` は `frontend/e2e/start-rails.sh` を流し、`bin/rails e2e:check`（test の環境で、rspec のテスト DB と別の DB を指し、心拍の生きている Solid Queue のプロセスが無いこと）・`bin/rails db:drop db:prepare`・`bin/rails e2e:prepare[ワーカー数]`（`lib/tasks/e2e.rake`）の順に、DB を作り直してから、Playwright のワーカーごとに、M32 の `DemoWorld.build(namespace: "w<ワーカー番号>", variant: :e2e)` で世界（受注側 1 社・発注側 2 社・各社のユーザー）を 1 組ずつ作り、返ったアカウントを `tmp/e2e/worlds.json` に書き出す。DB を作り直す工程は、世界を作るプロセスと別のコマンドにする。`DemoWorld` を読み込んだプロセスの中で `db:prepare` を呼ぶと、作り直した DB に構造を読み込まずに終わるからである。`DemoWorld` はジョブを claim せずにその場で流すので、`bin/jobs` は、このスクリプトが準備を終えてから起こす。Playwright 1.64 は `webServer` を `globalSetup` より先に起こす（`lib/runner` の `createGlobalSetupTasks` がプラグインの setup の後に `globalSetup` を並べる）ので、準備を `globalSetup` に置くと `bin/jobs` が先に動く。`e2e:prepare` は世界を作った後にも心拍の生きている Solid Queue のプロセスが無いことを確かめ、この順が崩れたら失敗する（OI-143）。`webServer` は SIGTERM で止め、`bin/jobs` に Solid Queue の登録を消させる。テストは、自分のワーカー番号（`parallelIndex`）の世界のアカウントでログインし、他の世界に書かない。
- **一覧のページ**：E2E（`frontend/e2e/list-pagination.spec.ts`）で、品目の一覧（`variant: :e2e` は 22 件で、1 ページの 20 件を超える。`spec/scenarios/demo_world_spec.rb` で件数を確かめる）を、名前の昇順で 2 ページ目まで読み、1 ページ目と 2 ページ目の行が重ならず、合わせて `totalCount` の件数になることを確かめる。並べ替えの見出しを押すと、URL の `sort`・`dir` と `orderBy` が変わり、1 ページ目に戻ることも確かめる。
- **画面の通し試験**：E2E に次の 2 本を置く。1 本目は、重要シナリオ S2（M26）を画面で通す。失効の後、発注側の取引先とカタログと出荷が空になり、発注登録が `NOT_PERMITTED` の文言になる。2 本目は、発注側の 2 社のユーザーで続けてログインし、前のテナントの伝票番号が画面に出ないことを確かめる。
- **流用元の規則**：流用元の `handbook/README.md` の E2E と見た目の規則を、次のとおり持ち込む。

  | 流用元の規則 | 本デモでの置き方 |
  |---|---|
  | 同じ種類の要素の寸法・そろえ・はみ出しを、最初のタスクで全画面について測る | 流用元の `e2e/support/tokens.ts`・`table-align.ts`・`contrast.ts` と、カードの高さ・はみ出し（`scrollWidth <= clientWidth`）の検査を写し、M33 の最初の作業で置く。測る画面の一覧は `app/` のルートのファイルから作り、手で並べない。足した画面が測られないまま通らないようにするためである |
  | 中身の違うデータを作ってから測る | `DemoWorld` の `variant: :e2e` が、最も長い品目名と取引先名、ボタンのある行と無い行、各状況の enum の止まっていられる全値の行を入れる（M32、OI-138・OI-139）。シードの短くそろった中身だけで測らない |
  | 寸法・色・フォーカスは、アニメーションと色の遷移が終わってから測る。キーは 1 つ押すごとにフォーカスの移りを待つ | 流用元の `e2e/support/style.ts`・`router.ts` の待ち方をそのまま使う |
  | 数える前に画面の変化を待ち、遷移の後は着いたことを先に確かめる | 同上。イベントで進む表示（発注 → 受注確定）はワーカーの処理を待つので、`expect.poll` と再読み込みで待ち、固定の時間は待たない |
  | 1 回だけ落ちたテストを、再実行で緑にして流さない | CPU の遅延（CDP の `Emulation.setCPUThrottlingRate`）で再現率を測り、待ち方の誤りか製品の競合かを分ける。Playwright の `retries` は 0 にする |
  | 集計の数字と、そこから飛ぶ一覧は、同じ条件で絞る | ダッシュボードの状況ごとの件数と、受注一覧のタブの件数と、かんばんの列の件数が一致することを E2E で確かめる。どれも M40 の同じ式で数える。安全在庫を下回る在庫の件数と、在庫の画面の切り替えの件数も同じく確かめる |
  | テストは、壊したときに落ちて初めて意味を持つ | 本リポジトリの壊して落ちる記録（`guides/dev-cycle.md`「テストから書く」）と同じに扱う |
  | 見せる前に、同じ種類の要素どうしをスクリーンショットで見比べる | 検収表（画面 × ライト・ダーク × 1280・1024・390px）のスクリーンショットを撮り、担当者が見比べてから作者に見せる。作者が受け入れるまで M33 を終えない |

  流用元の開発の進め方（台帳・交差レビュー・RED と GREEN の push の規約）と、配信先のエッジに掛かる上限の検査は持ち込まない。本書の「1 つのマイルストーンの進め方」と、`guides/dev-cycle.md` のレビューの回し方に従う。
- **CI**：`.github/workflows/ci.yml` にジョブを 2 つ足す。`frontend` は、`npm ci`・`npm run codegen:check`・`npm run lint`（コメントの検査を含む）・`npm run typecheck`・`npm run test:unit` を流す。`e2e` は、既存の test のジョブと同じ PostgreSQL 18 のサービスとロールの準備をし、Ruby と Node を入れ、`npx playwright install --with-deps chromium` の後に `npm run test:e2e` を流す。
- **サイクル 04 の逸脱検査から送った確かめ**：E2E が Rails のサーバーを起こす前に、`WEB_CONCURRENCY` の未設定・`0`・正の数・`auto` で Web（`METRICS_PROCESS=web`）を起こし、Puma が単一のモードで起きて exporter が値を出すかを確かめる（OI-142）。`0` が単一のモードなら、`guides/config.md`「exporter と値の置き場」を「クラスタのモードになる値」に具体化する。確かめた結果、未設定と `0` は単一のモードで起きて exporter が値を出し、`2` と `auto` はクラスタのモードで起きて `Platform::Metrics` が起動を止めたので、`guides/config.md` を「クラスタのモードになる値（正の数と `auto`）」に直した

**完了条件**

```sh
cd frontend && npm run codegen:check && npm run lint && npm run typecheck && npm run test:unit
cd frontend && npm run test:e2e
bundle exec rspec spec/graphql/query_budget_spec.rb spec/graphql/query_complexity_spec.rb spec/platform/metrics_subscriber_spec.rb   # 画面の問い合わせを frontend/graphql から読む
```

期待の不一致で最初に落とすのは、`frontend/e2e/list-pagination.spec.ts` の、品目の一覧の 1 ページ目と 2 ページ目が重ならず合わせて `totalCount` になることを確かめる example（画面の読み方を 1 ページずつに替える前は、流用元の画面が全件を読むので 2 ページ目へのリンクが無い）と、`spec/graphql/query_budget_spec.rb` の、画面の問い合わせのファイルの一覧が `frontend/graphql/` の query と一致することを確かめる example（読み先を替えて `spec/fixtures/graphql/screens/` を消す前は、一致しない）である。画面の部品が無いことによる読み込みの失敗は、RED に数えない。

次を、手で確かめる。`schema.graphql` から画面が使うフィールドを 1 つ消すと、`npm run codegen:check` か `npm run typecheck` が落ちる。`request.ts` に `"use cache"` を足すと、`npm run lint` が落ちる。一覧の画面の URL の値を `orderBy`・`filter` に写す関数で、並べ替えの向きを取り違えると、E2E の一覧のページの確かめが落ちる。作者が検収表のスクリーンショットを見て受け入れる。

**著者判断（決まったこと）**：計画は、次の 8 点と公開の時期に既定を置いて書き、作者が決めた（2026-10-12、OI-06〜OI-14）。担当者は、着手の前に台帳の結果の欄を読み直す。

1. **一覧の読み方**（OI-07。既定を変えた）：一覧は 1 ページずつ読み、並べ替え・絞り込み・件数はサーバーで行う（M39・M40、「作るもの 3」の一覧の読み方）。全件を読み切って画面で並べる形と、500 件での打ち切りはやめた。件数が増えても並びと件数が正しいことを優先したからである。
2. **状況のバッジの色**（OI-08。既定のまま）：流用元に無い状況（品番照合待ち・検収済・発注の各状況・出荷依頼・取り込み・請求書）は、意味の近い流用元の状況の色を使い回し、色のトークンを足さない。
3. **ログインの画面**（OI-09。既定のまま）：メールアドレスとパスワードの入力欄に、M32 のシードのアカウント（メールアドレスと、共通のパスワード）の一覧を並べ、押すと入力欄に入る。一覧は `db/seeds/demo_accounts.json` の 1 か所に置き、シードとフロントエンドの両方が読む。
4. **サイドバーと最初の画面**（OI-10。既定のまま）：テナントは発注側と受注側のどちらにもなりうるので、サイドバーには両方のグループを常に出す。ログインの直後は、`supplier.partnerships` が空でなければ受注側のダッシュボードへ、空なら発注側の発注一覧へ移す。
5. **セッションの期限**（OI-11。既定のまま）：Rails は、応答のたびにセッションの Cookie を書き直して期限を延ばす。サーバーコンポーネントは Cookie を書けないので、延びた Cookie は server action の応答でだけブラウザに写す。読むだけの利用では、期限はログインか最後の書き込みから 12 時間になる。
6. **入口に足すフィールド**（OI-12。既定のまま）：品目を ID で引く `supplier.item(id:)` と、サイドバーに自社の名前を出す `viewer.tenant` を足す。API の変更をまとめるため、足すのは M39 である。
7. **入荷の一覧**（OI-13。既定のまま）：発注をまたいだ入荷の一覧の入口（`buyer.inboundShipments`）は足さず、発注一覧の「入荷予定」のタブで代える。検収は発注詳細で行う。
8. **公開の配置**（OI-14。既定を変えた）：流用元と同じ Raspberry Pi の k3s に、Rails・Next・PostgreSQL・ジョブのワーカーを置き、Cloudflare Tunnel で公開する（M41）。訪問者ごとのデータの分離は作らず、全員が同じデモのデータを使い、毎日決まった時刻にシードから作り直す。

並べ替えの列を一覧の表に限ること（M39 の判断）は、流用元の画面の並べ替えと検索を減らすので、作者に確かめている（OI-144）。M33 を終える前に決まっていなければならない。

GitHub のリポジトリを public にする時期（OI-06）は、まだ決めない。M33 の完了条件に public にすることを入れず、決まるまで private のまま進める。

**範囲外**：公開の配置（M41）、訪問者ごとのデータの分離（著者判断 8）、流用元のデモの開始・サンプル表示・混雑の通知、API に無い操作（「作るもの 2」の末尾）、API で並べられない列での並べ替え（M39 の判断）、通知メールの設定画面、流用元のこれからの変更の取り込み（置き場所の判断の裏返る条件に当たるまで）。

**実装する文書の節**：`graphql-schema.md`「1 回のリクエストがたどる道」1・「視点ごとに型を分ける」・「状況の enum」・「エラー」・「ページングと N+1」、`guides/config.md`「CSRF を防ぐ前提：CORS を開けない」、`handoff.md`「目的」、流用元の `docs/specs/cycle-03-visual-refresh-spec.md` §2（トークン）・§3（外枠と共通部品）・§9（ダッシュボード）・§11（検収表）と `handbook/README.md`

**文書に残すこと**：画面の問い合わせの置き場を、本書の M17 と `graphql-schema.md`「ページングと N+1」で `frontend/graphql/` に書き直す。`guides/comments.md` の対象に `frontend/` を足す。`README.md` の「構成」に、フロントエンドの起動の手順を書く。

## M41 Raspberry Pi の k3s への配置

**目的**：作者の判断（OI-14）に従い、流用元のデモと同じ Raspberry Pi の k3s に、Rails（Web）・ジョブのワーカー・Next（画面）・PostgreSQL を置き、画面を Cloudflare Tunnel で公開する。全員が同じデモのデータを使い、毎日決まった時刻にシードから作り直す。判断の比べた案と裏返る条件は `adr/009` にある。リポジトリが作るのは、イメージ・マニフェスト・作り直しの仕組みと、それを確かめる spec までである。Raspberry Pi と Cloudflare のアカウントには触れず、実機での確かめは作者が行う手順として `deploy/README.md` に書く。

**作るもの**

1. イメージ（`adr/009` 決定 6）：Rails の `Dockerfile`（いまのもの）と、画面の `frontend/Dockerfile`（新しく作る。Next の `output: "standalone"` で、Node は M33 の CI と同じ版）を、`linux/arm64` で作る。CI に `images` のジョブを足し、ubuntu の GitHub ホストのランナーで QEMU と buildx を使って作る。PR では作るだけにし、main への push のときだけ `ghcr.io/ringoshogo/factory-ops-demo-rails/api:<git の SHA>` と `.../frontend:<git の SHA>` を GHCR へ push する。タグは git の SHA に固定し、`latest` を使わない（流用元と同じ）。キャッシュは GitHub Actions のキャッシュに置く。作った Rails のイメージを QEMU の上で起こし、`SECRET_KEY_BASE_DUMMY=1` を渡して `bin/rails runner` で本番の環境（`eager_load`）が読み込めることを確かめる。
2. マニフェスト（`deploy/`）：流用元と同じく、Kustomize の 1 つの `kustomization.yaml` に並べる（環境が 1 つなので、base と overlays に分けない）。名前空間は `factory-ops-rails` にし、流用元の `factory-ops` と分ける。

   | 種類 | 名前 | 中身 |
   |---|---|---|
   | Deployment | `web` | Rails の `bin/rails server`（Thruster を通さない。ブラウザから届かないので、圧縮と静的なファイルの配信が要らない）。Puma は単一のモード（`WEB_CONCURRENCY` を設定しない。OI-142）で 3 スレッド。`/up` を readiness と liveness に使う |
   | Deployment | `jobs` | `bin/jobs`。`SOLID_QUEUE_SUPERVISOR_MODE=async` で、ワーカー・ディスパッチャ・スケジューラを 1 つのプロセスのスレッドで動かす（`adr/009` 決定 5） |
   | Deployment | `frontend` | Next の standalone のサーバー。Rails は Service の `web` を名前で呼ぶ |
   | Deployment | `postgres` | 公式の `postgres` のイメージを、18 の小版まで固定したタグで使う（arm64 を含む）。PVC `postgres-data`（`local-path`・`ReadWriteOnce`・5Gi）を、`Recreate` で掴む。18 のイメージはデータを `/var/lib/postgresql/18/docker` に置くので、PVC は `/var/lib/postgresql` に付ける（流用元の 16 の `/var/lib/postgresql/data` を写さない。本リポジトリの `compose.yaml` と同じ）。初回の起動で、所有ロールとアプリのロールを Secret のパスワードで作るスクリプト（`docker/initdb/01_roles.sql` と同じロールと属性）を流す。業務の DB は初期化で作らず、所有ロールが `db:prepare` で作る。DB の持ち主を所有ロールにし、作り直しで所有ロールが消せるようにするためである |
   | Service | `web`・`frontend`・`postgres` | どれも `ClusterIP` |
   | Ingress | `frontend` | k3s の Traefik。ホスト名は OI-145。Rails には Ingress を置かない（`adr/009` 決定 2） |
   | Job | `migrate` | 所有ロールで `bin/rails db:prepare db:grant_app_role` を流す |
   | CronJob | `daily-reset` | 作るもの 3 の作り直し |
   | ServiceAccount・Role・RoleBinding | `daily-reset` | 名前空間の中で、Deployment の `get`、`deployments/scale` の `get`・`patch`、Pod の `list` だけを許す |

   各コンテナに渡す環境変数は次のとおりである。値を持つものは Secret から、ほかはマニフェストに書く。

   | 環境変数 | `web` | `jobs` | `frontend` | `migrate` | `daily-reset` | なぜ |
   |---|---|---|---|---|---|---|
   | `RAILS_ENV=production` | ○ | ○ | — | ○ | ○ | 本番の環境の設定で公開する（`adr/009` 代替案 C） |
   | `SECRET_KEY_BASE` | ○ | ○ | — | ○ | ○ | `config/credentials.yml.enc` を使わない。セッションの Cookie の暗号化に要る |
   | `DB_HOST`・`DB_PORT` | ○ | ○ | — | ○ | ○ | 本番の `config/database.yml` は接続先を持たないので、`production` の 2 つの設定が開発と同じ形でこの 2 つを読むように直す |
   | `DB_APP_USER`・`DB_APP_PASSWORD` | ○ | ○ | — | ○ | ○ | `db:grant_app_role` とシードがアプリのロールの名前を読む |
   | `DB_OWNER_USER`・`DB_OWNER_PASSWORD` | — | — | — | ○ | ○ | 所有ロールは RLS を素通りするので、DB を作る工程にだけ渡す（`config/database.yml` の `production`） |
   | `RAILS_MAX_THREADS` | 3 | 20 | — | — | — | `jobs` は async のモードで全ワーカーが 1 つの接続プールを分け合う。Solid Queue の README「Fork vs. async mode」は、プロセスの中のワーカーの要るものを足し合わせるとし、ワーカーごとにスレッドに加えてポーリングと心拍の接続を使う。`config/queue.yml` のスレッドの和 8 に、4 つのワーカーの 2 つずつとディスパッチャ・スケジューラ・スーパーバイザの分を足して 20 にする |
   | `FRONTEND_ORIGIN` | ○ | — | — | — | — | 取り込みのファイルの受け口が、ブラウザの `Origin` を公開の画面のオリジン（OI-145）と比べる（`config/application.rb`） |
   | `NOTIFICATIONS_PROVIDER=file_system` | ○ | ○ | — | — | ○ | 作るもの 5 |
   | `DEMO_WORLD_ENABLED=1` | — | — | — | — | ○ | 作るもの 4 |
   | `SHARED_DEMO_ACCOUNTS=1` | ○ | — | — | — | — | 作るもの 7（OI-149） |
   | `SOLID_QUEUE_SUPERVISOR_MODE=async` | — | ○ | — | — | — | `adr/009` 決定 5 |
   | Rails の URL（M33 が決めた名前） | — | — | ○ | — | — | Next のサーバーが `http://web:3000` を呼ぶ |

   PostgreSQL の `max_connections` は、`web` の 3 と `jobs` の 20 に、`migrate`・`daily-reset`・手の作業の分を足して 40 にする。

   Secret はリポジトリに置かず、作者が `kubectl create secret` で入れる（流用元と同じ）。マニフェストが参照する Secret の名前とキーは `deploy/README.md` の表に書き、`deploy/preflight.sh` が、マニフェストの `secretKeyRef` と `imagePullSecrets` から集めた名前とキーが名前空間にあることを確かめる（流用元の `deploy/preflight.sh` の形。集める正本はマニフェスト）。
3. 毎日の作り直し（`adr/009` 決定 3）：CronJob `daily-reset` が、毎日 OI-146 の時刻（`timeZone: Asia/Tokyo`）に、Rails のイメージで `bin/rails demo:reset` を流す。`concurrencyPolicy: Forbid` にし、`startingDeadlineSeconds` を置いて、Raspberry Pi が止まっていて時刻を過ぎても、起動の後に決めた時間の内なら流す。Job は `backoffLimit: 0`（作り直しを途中から繰り返して DB を何度も消さない）と `activeDeadlineSeconds: 1800` を持つ。`demo:reset`（`lib/tasks/demo.rake`）は次の順に進む。
   1. 本番の環境では、作るもの 4 の条件を満たさなければ、Kubernetes の API も DB も触らずに例外で止まる
   2. Kubernetes の API で `web` と `jobs` の Deployment を 0 にし、両方のラベルの Pod の一覧が空になるまで待つ（上限 5 分。超えたら手順 5 へ進んで例外で終える）。Deployment の `status.replicas` は終了中の Pod を数えないので、Pod の一覧で待つ。DB を消す間に接続が残らないようにし、シードがその場で流すジョブを `bin/jobs` が同時に流さないようにする（OI-143 と同じ理由）
   3. 自分の接続をプールに返してから（`connection_handler.clear_all_connections!`）、所有ロールで DB を消して作り直し（`db:drop`・`db:prepare`）、アプリのロールに権限を付ける（`db:grant_app_role`）。Rails は本番の環境の DB を消すタスクを `ActiveRecord::ProtectedEnvironmentError` で止め、`DISABLE_DATABASE_ENVIRONMENT_CHECK` があれば確かめを飛ばす（activerecord 8.1.4 の `lib/active_record/tasks/database_tasks.rb` の `check_protected_environments!`）。`demo:reset` は、手順 1 の条件を満たしたときにだけ、この変数をタスクの中で立てて `db:drop` を呼び、終わったら戻す
   4. `DemoWorld.build(namespace: "", variant: :seed)` でデモの世界を作る
   5. 成功しても失敗しても、`web` と `jobs` の Deployment を 1 に戻す（`ensure`）。作り直しに失敗した日も画面を止めないためである。作り直しの Pod が OOM か Raspberry Pi の停止で殺されると `ensure` は走らないので、`deploy/README.md` に戻し方（`kubectl scale --replicas=1`）を書く。次の日の作り直しも、最後に 1 に戻す

   Kubernetes の API は、Pod の ServiceAccount のトークンで Net::HTTP から呼び、`kubectl` のイメージを足さない。監査ログの行は、追記だけの表で、所有ロールでも消せず `TRUNCATE` もトリガーが止める（`architecture/data-model.md`「監査ログ（`platform`）」）。作り直しは行を消さず DB ごと消すので、行の書き換えと削除を止める仕組みは変えない。ただし、公開の配置の監査ログは 1 日で消え、保存期間（7 年）を守らない。公開の配置は業務の記録を持たないデモであり、DB を消す工程は `DEMO_WORLD_ENABLED` を渡した作り直しだけで、本物の本番の配置では手順 1 で止まるからである（`adr/009` 決定 3）。
4. 本番の環境でデモの世界を許す条件（`adr/009` 決定 4）：いまは、`DemoWorld`・`Partnerships::Onboarding`・`Inventory::Stocks.set_safety_stock` の 3 つが、本番の環境で `ProductionEnvironment` を上げて止まる（`git grep ProductionEnvironment` で集めた一覧。この一覧を正本にする）。環境変数 `DEMO_WORLD_ENABLED=1` を渡したプロセスでだけ、本番の環境でも動くようにする。条件は `packs/platform` の 1 か所に置き、3 つがそれを読む。この変数は `daily-reset` にだけ渡し、`web`・`jobs`・`migrate` には渡さない。
5. メールを送らない：公開の配置のアカウントのメールアドレスは実在しないので、メールを外へ送らない。本番の環境の通知の送り先（`config.x.notifications.provider`）を環境変数 `NOTIFICATIONS_PROVIDER` で `file_system` に替えられるようにし、`sendgrid`（省いたとき）と `file_system` のほかの値は起動で落とす。配置では `file_system` を渡し、書き出す先（`tmp/mails`）を `emptyDir` にする。`emptyDir` は Pod と一緒に消え、作り直しが毎日 `web` と `jobs` の Pod を作り直すので、溜まるのは 1 日分である。大きさの上限（`sizeLimit`）を超えると kubelet が Pod を追い出すので、上限は 1 日分のメールより十分に大きくする。
6. セッションの Cookie を書く：本番の環境のセッションの Cookie は `Secure` で（`config/application.rb` の `session_store`）、actionpack 8.1.4 は `request.ssl?` が偽の応答に `Secure` の Cookie を書かない（`lib/action_dispatch/middleware/cookies.rb` の `write_cookie?`）。Next は Rails を http で呼ぶので、このままではログインの応答に `Set-Cookie` が無く、M33 の認証が Cookie を写せない。本番の環境で `config.assume_ssl = true` にする。TLS は Cloudflare で終わり、Rails には Next からしか届かないからである（`adr/009` 決定 2）。Rails はこのとき `ActionDispatch::AssumeSSL` をミドルウェアに足すので、本番の環境のミドルウェアの並びを許した一覧と比べる `spec/platform/logging_spec.rb`（`adr/008`）の一覧に足す。
7. 共有のアカウントのログアウト：OI-149 の既定のとおり、公開の配置ではログアウトでセッションの世代を進めない。`SHARED_DEMO_ACCOUNTS=1` を渡した `web` では、`DELETE /session` は Cookie を消すだけにする。世代を進めると、同じアカウントでログインしているほかの訪問者のセッションがすべて切れるからである（`architecture/graphql-schema.md`「1 回のリクエストがたどる道」1）。このとき、ログアウトの前に写し取られた Cookie は使えるままになる（`SessionsController#destroy` が世代を進める理由）。公開の配置では資格情報がログインの画面に出ているので、この保証を外す。作者が OI-149 で既定を変えれば、この項を直す。
8. 資源の見積もり：各コンテナに、次の requests と limits を書く。値は arm64 の実機で測っていない見積もりで、作者が実機で測って直す（作者の手順 4）。

   | コンテナ | requests（CPU・メモリ） | limits（CPU・メモリ） | なぜこの値か |
   |---|---|---|---|
   | `web` | 100m・256Mi | 1000m・512Mi | 全コードを読み込んだ Rails の 1 プロセスは、jemalloc で 200〜300MiB を見込む。単一のモードなので、プロセスは 1 つである |
   | `jobs` | 100m・256Mi | 1000m・512Mi | async のモードで 1 プロセスにする。fork のモードでは、スーパーバイザ・ワーカー 4 つ・ディスパッチャ・スケジューラの 7 プロセスがそれぞれ Rails を抱え、1GiB を超えうる |
   | `frontend` | 50m・128Mi | 500m・384Mi | Node の 1 プロセス。サーバーコンポーネントの描画の間だけ増える |
   | `postgres` | 100m・256Mi | 1000m・512Mi | 流用元の PostgreSQL と同じ上限。`shared_buffers` は既定の 128MB で、接続ごとのメモリが `max_connections` の 40 まで増える |
   | `migrate`・`daily-reset` | 100m・256Mi | 1000m・768Mi | Rails を読み込み、作り直しはシードの間にイベントのジョブをその場で流す。毎日の数分だけ動き、作り直しの間は `web` と `jobs` が止まっている |

   常に動く 4 つのコンテナの limits の和は約 1.9GiB になる。流用元の limits の和（約 0.9GiB、Job を含む）と k3s 自身を足すと、3GiB 前後になる。Raspberry Pi のメモリが 4GB なら余裕が小さいので、作者に機種とメモリを確かめる（OI-147）。CPU の limits は、1 つのコンテナが流用元のデモの分まで使い切らないための上限で、コア数を超えない。
9. 作者の手順（`deploy/README.md`）：作者が実機で行うことを、この順に書く。コマンドは、その実行にだけ効く形（`ssh` の先のコマンド、引数）で書き、ホストの全体の設定を変えるコマンドを書かない（`guides/dev-cycle.md`「文書の置き場と、書く前の振り分け」）。
   1. 名前空間と Secret を作る（値はその場で生成し、どこにも書き残さない）。GHCR の読み取りの Secret は、流用元の `ghcr-pull-secret` と同じ作り方で、この名前空間に作る
   2. `deploy/preflight.sh` で Secret がそろったことを確かめ、イメージのタグを main の SHA にして適用し、`migrate` の完了を見てから `web` が ready になるのを待つ
   3. 手で 1 回 `daily-reset` を流し（`kubectl create job --from=cronjob/daily-reset`）、ログにシードのアカウントが出ることと、`web` と `jobs` が 1 に戻ることを確かめる。CronJob の `timeZone` と `startingDeadlineSeconds` が効くかも、Raspberry Pi を止めた日に 1 回見る
   4. `kubectl top pods`（k3s に同梱の metrics-server）で、両方の名前空間の Pod のメモリを測り、作り直しの間の最大も見て、作るもの 8 の値を直す PR の材料にする。取り込み（5 万行の CSV）を流しながら発注を登録し、受注が確定するまでの時間を画面で測る（`adr/009`「見直す条件」の async のモードの確かめ）
   5. Cloudflare Tunnel に、OI-145 のホスト名を Traefik へ送る公開のホスト名を足す。流用元の tunnel の設定はリポジトリの外にあるので、その置き場で足す。流用元のホストに掛けたレート制限と Bot Fight Mode を、このホスト名にも掛ける
   6. 公開の URL でシードのアカウントでログインし、受注一覧と発注一覧が出ること、Rails の Service が外から届かないこと、流用元のデモがこれまでどおり動くことを確かめる

テナントの境界：業務の表・RLS・policy は変えない。作り直しは DB ごと作り直し、行を書き換えない。所有ロールの資格情報を Web とワーカーに渡さない形は、いまの `config/database.yml` の規則のままである。コンテキストの境界：作り直しは `lib/` のタスクで、パッケージの公開 API は `DemoWorld` がいまの形で呼ぶ。本番の環境でデモの世界を許す条件だけを `packs/platform` に足し、3 つの公開 API がそれを読む。

**完了条件**

```sh
bundle exec rspec spec/platform/deploy_manifests_spec.rb spec/platform/demo_reset_spec.rb spec/platform/production_boot_spec.rb spec/platform/logging_spec.rb spec/scenarios/demo_world_spec.rb packs/partnerships/spec/public/partnerships/onboarding_spec.rb packs/inventory/spec/public/inventory/stocks_spec.rb spec/requests/sessions_spec.rb   # 0 failures
```

ほかに、M41 の PR で CI の `images` のジョブが通ること（arm64 の 2 つのイメージを作り、Rails のイメージで本番の環境を読み込める）を確かめる。

期待の不一致で最初に落とすのは、`deploy_manifests_spec.rb` の、マニフェストの規則の example である。spec は `deploy/*.yaml` を読み、次を確かめる。`Secret` の種類が無い。すべてのコンテナが CPU とメモリの requests と limits を持つ。イメージがタグ付きで `latest` を使わない。作るもの 2 の環境変数の表のとおりに、各コンテナが変数を持ち、表で「—」の変数を持たない（`DB_OWNER_*` は `migrate` と `daily-reset` だけ、`DEMO_WORLD_ENABLED` は `daily-reset` だけ）。`jobs` の `RAILS_MAX_THREADS` が、`config/queue.yml` のワーカーごとのスレッドに 2 を足した和に 4 を足した値以上である。Ingress は `frontend` の 1 つだけで、Service はどれも `ClusterIP` である。`postgres` の PVC が `/var/lib/postgresql` に付く。CronJob は `timeZone: Asia/Tokyo`・`concurrencyPolicy: Forbid`・`backoffLimit: 0`・`activeDeadlineSeconds` を持つ。Role の規則が作るもの 2 の 4 つだけである。`deploy/README.md` の Secret の表が、マニフェストから集めた名前とキーと一致する。ほかは、次の壊して落ちる記録を spec ごとに証跡の「実装の記録」に残す。

- `demo_reset_spec.rb`：Kubernetes の API を WebMock で受け、DB の作り直しとシードを差し替えて確かめる。本番の環境で `DEMO_WORLD_ENABLED` が無いか `1` でなければ、Kubernetes の API も DB のタスクも呼ばずに例外で止まる。`1` なら、0 にして Pod の一覧が空になってから作り直し、`DISABLE_DATABASE_ENVIRONMENT_CHECK` を作り直しの間だけ立てる。作り直しが例外で終わっても 1 に戻す。入口の条件を外すと無いときの example が、`ensure` を外すと失敗の example が、Pod の一覧の待ちを外すと Pod が残っている間に作り直しを始めないことの example が落ちる
- `demo_world_spec.rb`・`onboarding_spec.rb`・`stocks_spec.rb`：本番の環境で `DEMO_WORLD_ENABLED` が無ければ例外、あれば動く。`demo_world_spec.rb` は `DemoWorld.build` を最後まで流して確かめる（3 つのうち 1 つでも条件を読まなければ、途中で止まって落ちる）。条件を外すと、無いときの example が落ちる
- `production_boot_spec.rb`：子のプロセスで本番の環境を起こす（`spec/platform/logging_spec.rb` の子のプロセスと同じ形）。`NOTIFICATIONS_PROVIDER` の未設定・`file_system`・ほかの値で、送り先と起動の失敗を確かめる。http の `POST /session` の応答が `Secure` のセッションの Cookie を `Set-Cookie` に持つことを確かめる。本番の環境の DB はテストと CI に無いので、子のプロセスの中で `Partnerships::Authentication.authenticate` を差し替えてから、`Rack::MockRequest` で `POST /session` を流す。`assume_ssl` を外すと、この example が落ちる
- `sessions_spec.rb`：`SHARED_DEMO_ACCOUNTS=1` のとき、`DELETE /session` でセッションの世代が進まず、同じユーザーのほかのセッションが続くことを確かめる。無いときは、いまのとおり世代が進んでほかのセッションが切れる。条件を外すと、変数があるときの example が落ちる

**作者が実機で確かめること**：作るもの 9 の手順 1〜6。結果（測ったメモリ、公開の URL で確かめたこと、流用元のデモが動くこと）を、作者が PR か台帳に書く。実機の確かめは M41 の完了条件に入れず、作者が結果を書くまで公開しない。

**範囲外**：訪問者ごとのデータの分離（著者判断 8）、GitHub のリポジトリを public にすること（OI-06）、メトリクスの収集（Prometheus を置かない。`METRICS_PROCESS` を設定しないので exporter は立たない）、バックアップ（毎日シードから作り直すので要らない）、GitOps による適用、流用元の配置の変更。

**実装する文書の節**：`adr/009`、`config/database.yml` の `production`、`architecture/data-model.md`「RLS」・「監査ログ（`platform`）」、`architecture/graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」・「監査ログ」・「1 回のリクエストがたどる道」、`guides/config.md`「ジョブ」・「環境ごとの設定」、流用元の `deploy/README.md`・`deploy/preflight.sh`・`deploy/daily-reset-cronjob.yaml`・`docs/plans/cycle-01-t34-release-runbook.md`

**文書に残すこと**：本番の環境でデモの世界を作れる条件（`DEMO_WORLD_ENABLED`）を、いま「本番の環境では呼べない」「本番の環境では動かない」と書く 3 か所に書く（`architecture/graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」の操作者のいない入口の段落と「監査ログ」の `DemoWorld` の段落、`architecture/data-model.md`「RLS」の `Partnerships::Onboarding`）。`architecture/data-model.md`「監査ログ（`platform`）」に、公開の配置は保存期間と「表を落とす DDL はレビューで止める」の対象外で、毎日 DB ごと作り直すことと、そう言える条件を書く。`architecture/graphql-schema.md`「1 回のリクエストがたどる道」1 に、`SHARED_DEMO_ACCOUNTS` のときのログアウトを書く。`guides/config.md`「環境ごとの設定」に `DEMO_WORLD_ENABLED`・`NOTIFICATIONS_PROVIDER`・`SHARED_DEMO_ACCOUNTS`・`DB_HOST`・`assume_ssl` を、「ジョブ」に配置では async のモードで動かすことと接続プールの決め方を書く。`README.md` の「構成」に `deploy/` を足し、`deploy/README.md` を指す。実機で測った値で作るもの 8 を直したら、`adr/009` の「確認した事項」に書く。
