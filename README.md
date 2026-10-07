# factory-ops-demo-rails

Rails で B2B SaaS を 0 から作るときの設計判断を、実際に動くアプリとして示すデモ。設計の決定事項（`docs/architecture/decisions.md`）を正本とし、各判断がコードのどこで機械的に守られているかを辿れるようにする。

題材は姉妹プロジェクト `factory-ops-demo`（Go＋Next.js）と同じく、架空の機械部品メーカーの受発注・在庫管理である。本デモはこれに請求を加える。もう 1 つの違いはマルチテナントにあり、本デモは **相互アクセス型**（取引関係にあるテナント同士が、相手のデータの一部を参照・操作する）を採る。決定事項の文書は完全分離型も扱うが、本デモでは相互アクセス型に関わる判断を実装の対象にする。

> 本リポジトリのデータ・企業名はすべて架空で、実在の企業・業務データとは関係ない。

## 構成

- **バックエンド**：Rails（API モード）＋ PostgreSQL
- **API**：GraphQL
- **フロントエンド**：factory-ops-demo の Next.js を流用する。画面部品はそのまま使い、データ取得層を REST から GraphQL へ書き換え、発注側の画面を追加する
- **コードの置き場**：業務のコードは、コンテキストごとに `packs/<パッケージ>/app/` に置く。他のパッケージから呼べるのは `app/public/` の下だけで、依存してよい先は各 `package.yml` に書く。どちらも `bin/packwerk check` が CI で検査する。Rails の基底クラスは `packs/platform` にある

## 開発環境

開発者は、手元で最初に次を実行する。DB は `compose.yaml` の PostgreSQL 18 をポート 5433 で立てる。

```sh
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"   # pg_dump 18（brew install libpq）
bin/setup --skip-server
bundle exec rspec
```

DB には 2 つのロールで接続する。アプリとテストは RLS が掛かる `factory_app`、DB のタスクは表の所有者の `factory_owner` を使い、どちらも `bin/setup` が作る（`docs/architecture/data-model.md`「RLS」）。本番では、`factory_owner` の資格情報（`DB_OWNER_USER`・`DB_OWNER_PASSWORD`）をマイグレーションの工程にだけ渡し、Web とワーカーのプロセスには渡さない。M3 より前に作った DB は `postgres` の持ち物なので、`bin/rails db:drop` が通らない。その場合は `docker compose down -v` でボリュームごと作り直す。

pg_dump は 18 系を使う。18 未満の pg_dump は 18 のサーバーに対して動かず、`db/structure.sql` を書けないため、`bin/setup` は 18 未満なら止まる。Ruby は `.ruby-version` の版を rbenv で入れる。

## ドキュメント

| ファイル | 内容 |
|---|---|
| `docs/handoff.md` | 引き継ぎ。作業の現在地、決まったこと・決まっていないこと、次にやること。再開時に最初に読む |
| `docs/architecture/decisions.md` | 設計の決定事項。最初の 1 か月で決める順と、各論点の「既定の推奨・裏返る条件・撤退コスト」 |
| `docs/architecture/context-map.md` | コンテキストマップ。6 つのコンテキスト（取引関係・購買・受注・在庫・出荷・請求）と、その間のつなぎ方・テナントの所有 |
| `docs/architecture/data-model.md` | データモデル。テナントの持ち方、各コンテキストのテーブル、イベントの冪等キー、RLS ポリシー |
| `docs/architecture/graphql-schema.md` | GraphQL スキーマ。発注側と受注側の視点の型、相手側へたどれないことの保証、認可の基底クラス、クエリと mutation が呼ぶ公開 API |
| `docs/implementation-plan.md` | 実装計画。骨組みから業務機能までのマイルストーンと、各マイルストーンが機械で守るようにする規則・完了条件 |
| `docs/guides/bin.md` | `bin/` の各スクリプトの役割。誰がいつ流すか、Rails の生成物から何を変えたか |
| `docs/guides/config.md` | `config/` の各ファイルの役割。生成のままか変えたかと、変えた理由 |
| `docs/guides/packs-and-packwerk.md` | `packs/` 構成と packwerk の入門。2 つの検査、CI で落ちる場所、パッケージ・依存・公開 API を足す手順 |
| `docs/adr/001-スキーマ管理にridgepoleを採用しない.md` | スキーマ管理に Rails マイグレーション＋`structure.sql` を選ぶ理由 |
| `docs/adr/002-packwerkを初日からCIで強制する.md` | `packs/` 構成と packwerk の依存・プライバシーチェックを初日から CI で強制する理由 |
| `docs/adr/003-主キーにUUIDv7を使う.md` | 主キーを UUIDv7 にし、DB で生成する理由 |
| `docs/adr/004-GraphQLの型を視点ごとに分けnodeを置かない.md` | 1 つのスキーマで型を視点ごとに分け、汎用の `node` を置かない理由 |
| `docs/adr/005-イベントのジョブをトランザクション内で登録する.md` | Solid Queue を業務 DB と同じ接続に置き、イベントのジョブを業務のトランザクションの中で登録する理由 |

## 状態

`docs/implementation-plan.md` の M3（テナントの強制（DB 側））まで実装した。現在地は `docs/handoff.md` を見る。
