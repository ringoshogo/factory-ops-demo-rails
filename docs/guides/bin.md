# bin/ のスクリプト

`bin/` には、このリポジトリで使うコマンドの入口が並ぶ。多くは binstub（Gemfile で固定した版の gem を、`bundle exec` を付けずに起動する小さなスクリプト）である。この文書は、開発者が手元で最初に使うもの、コミットの前に流す検査、CI が使うもの、本番のコンテナが使うものの順に、各ファイルの役割と、Rails が生成したものから何を変えたかを示す。

各ファイルの出自は次の 4 つに分かれる。

- **Rails 生成**：`rails new` が作ったもの。手を入れたものは、その節に変更点と理由を書く
- **Solid Queue 生成**：`solid_queue:install` が作ったもの
- **Bundler 生成**：`bundle binstub <gem>` が作ったもの
- **本デモで書いたもの**

## 手元で最初に使う

開発者は、リポジトリを取得したら `bin/setup --skip-server` を 1 回流し、以後は `bin/rails` と `bin/dev` で作業する（README「開発環境」）。

| ファイル | すること | 使う人・時機 | 出自 |
|---|---|---|---|
| `bin/setup` | gem の導入、DB の起動とロールの作成、`db:prepare`、ログと一時ファイルの掃除。`--skip-server` を付けないと最後に `bin/dev` を起動する。`--reset` を付けると `db:reset` も流す | 開発者が最初と、Gemfile やマイグレーションが変わった後に。`bin/ci` の最初の工程 | Rails 生成（変更あり） |
| `bin/dev` | `bin/rails server` を起動するだけ | 開発者がサーバーを立てるとき | Rails 生成 |
| `bin/rails` | `rails` コマンドの入口。`db:*`・`console`・`runner`・`generate` など | 開発者が日常的に | Rails 生成 |
| `bin/rake` | Rake の入口。`bin/rails` からも同じタスクを呼べる | ほぼ使わない | Rails 生成 |

### bin/setup で変えたこと

生成されたままの `bin/setup` は、DB がすでに動いていて、`config/database.yml` のユーザーで接続できることを前提にする。本デモの DB は、`compose.yaml` の PostgreSQL 18 と、2 つの DB ロールを前提にしている。そこで、`db:prepare` の前に次の 3 つを足した。

1. **pg_dump の版を確かめ、18 未満なら止まる。** 18 未満の pg_dump は 18 のサーバーに対して動かず、`db/structure.sql` を書けない（[ADR 001](../adr/001-スキーマ管理にridgepoleを採用しない.md) 決定 6）。
2. **`docker compose up -d --wait db` で DB を起動する。**
3. **`docker/initdb/01_roles.sql` を psql で流し、所有ロール `factory_owner` とアプリのロール `factory_app` を作る。** compose の初期化スクリプトはボリュームを初めて作るときにしか流れないので、既存のボリュームにもここで作る（[data-model.md「RLS」](../architecture/data-model.md#rls)）。

`db:prepare` は所有ロールの接続で流れ、終わった後に `lib/tasks/db_roles.rake` がアプリのロールへ権限を付与する。2 つのロールの分け方は [config.md「DB の接続」](config.md#db-の接続) にある。

### bin/dev がジョブを処理しないこと

`bin/dev` はサーバーだけを起動し、Solid Queue のワーカーは起動しない。開発環境でイベントを受け手まで流したいときは、開発者が別の端末で `bin/jobs` を起動する。テストはワーカーを使わず、`spec/support/events.rb` の `deliver_enqueued_events` でイベントを届ける（[ADR 005](../adr/005-イベントのジョブをトランザクション内で登録する.md) 決定 6）。

## コミットの前に流す検査

開発者は、PR を出す前にこれらを手元で流す。CI も同じ検査を流す。

| ファイル | すること | 出自 | 動機 |
|---|---|---|---|
| `bin/rubocop` | `.rubocop.yml` を明示して RuboCop を動かす。`.rubocop.yml` は rubocop-rails-omakase を継承し、カスタム Cop `FactoryOps/EventJobEnqueue`・`FactoryOps/NoHistoryComment`（`lib/rubocop/cop/`）を足している | Rails 生成 | `EventJobEnqueue` は [ADR 005](../adr/005-イベントのジョブをトランザクション内で登録する.md) 決定 3、`NoHistoryComment` は [comments.md「機械で止めるもの」](comments.md#機械で止めるもの) |
| `bin/packwerk` | packwerk の入口。`validate` で設定の整合を、`check` で依存とプライバシーの違反を調べる | Bundler 生成（M2 で追加） | [ADR 002](../adr/002-packwerkを初日からCIで強制する.md)、[packs-and-packwerk.md](packs-and-packwerk.md) |
| `bin/check-structure` | `db/structure.sql` が、マイグレーションを流した結果とも、読み込み直して書き出した結果とも一致することを確かめる | 本デモで書いたもの | [ADR 001](../adr/001-スキーマ管理にridgepoleを採用しない.md) |
| `bin/check-open-items` | 残件と改善の候補の 2 つの台帳の形と、追跡しているファイルに書いた `OI-NN`・`IB-NN` が台帳にあることを確かめる。`--due M<番号>` を付けると、引当先がそのマイルストーンの `open` と `blocked-user` が残っていれば失敗する。`--text` で PR の本文も確かめる | 本デモで書いたもの | [dev-cycle.md「機械で守ること」](dev-cycle.md#機械で守ること) |
| `bin/test-layers` | rspec の JSON の出力（`--format json --out tmp/rspec.json`）を読み、テストの層ごとの件数・割合・時間を表にする。どの層の置き場にも当たらないファイルがあれば失敗し、割合が目安を外れたら警告の注釈を出す。`GITHUB_STEP_SUMMARY` があれば、表をジョブの要約にも書く | 本デモで書いたもの | [testing.md「テストの層」](testing.md#テストの層) |
| `bin/check-schema-compat` | 基準の ref（`BASE_REF`、既定は `origin/main`）と HEAD の分岐点の `schema.graphql` と、作業中の `schema.graphql` を比べ、非推奨を経ない破壊的変更があれば失敗する。例外は `docs/graphql/breaking-changes.yml` から読む。CI ではまだ流していない（基準の main に `schema.graphql` が入ってから足す） | 本デモで書いたもの | [graphql-schema.md「互換の判定」](../architecture/graphql-schema.md#互換の判定) |
| `bin/brakeman` | Brakeman（Rails のコードの静的なセキュリティ検査）。`--ensure-latest` を付け、古い版なら失敗させる | Rails 生成 | — |
| `bin/bundler-audit` | Gemfile.lock の gem に既知の脆弱性が無いかを調べる。無視する CVE は `config/bundler-audit.yml` に書く | Rails 生成 | — |
| `bin/ci` | `config/ci.rb` に並べた工程を順に流す、手元用の CI | Rails 生成 | 工程は [config.md「CI の工程」](config.md#ci-の工程) |

`bin/packwerk` の中にある `bin/bundle` の分岐は、Bundler の binstub の定型である。本リポジトリに `bin/bundle` は無いので、その分岐は通らない。

### bin/check-structure が確かめる 2 つの往復

マイグレーションを書いた開発者は、`db/structure.sql` を `git add` してから `bin/check-structure` を流す。差分は `git diff`（作業ツリーと index の比較）で取るからである。スクリプトは次の 2 つを順に確かめ、どちらかで差分が出たら失敗する。

1. **マイグレーションを流した結果**：空の DB に `db:migrate` を流し、書き出された `structure.sql` が元と一致するか。空の DB への `db:migrate` は、`structure.sql` があるとマイグレーションを流さずに読み込むだけになるので、スクリプトは `structure.sql` を `tmp/` へ退避してから流す。
2. **読み込み直した結果**：`structure.sql` を `db:schema:load` で読み込み、`db:schema:dump` で書き出し直したものが元と一致するか。

スクリプトは開発の DB を消して作り直すので、開発の DB に入れたデータは消える。`SKIP_TEST_DATABASE=true` を付けて流すため、テストの DB は消えない。

## CI が使うもの

GitHub Actions（`.github/workflows/ci.yml`）は `bin/ci` を呼ばず、3 つのジョブで各スクリプトを直接呼ぶ。

| ジョブ | 流すもの |
|---|---|
| `scan_ruby` | `bin/brakeman --no-pager`、`bin/bundler-audit` |
| `lint` | `bin/rubocop -f github`、`bin/packwerk validate && bin/packwerk check`、`bin/check-open-items`（PR では本文を `--text -` で渡す） |
| `test` | psql で `docker/initdb/01_roles.sql`、`bin/rails db:test:prepare`、`bundle exec rspec --format progress --format json --out tmp/rspec.json`、`bin/test-layers tmp/rspec.json`、`bin/check-structure` |

`test` のジョブは `bin/setup` を流さない。サービスのコンテナには初期化スクリプトを渡せないので、ロールはワークフローが psql で作る。

## 本番のコンテナが使うもの

`Dockerfile` は、`ENTRYPOINT` に `bin/docker-entrypoint`、`CMD` に `./bin/thrust ./bin/rails server` を指定する。ジョブのワーカーは、同じイメージを `bin/jobs` で起動する。

| ファイル | すること | 出自 |
|---|---|---|
| `bin/docker-entrypoint` | 受け取ったコマンドをそのまま `exec` する | Rails 生成（変更あり） |
| `bin/thrust` | Thruster（Puma の前に立つ HTTP プロキシ。圧縮・キャッシュ・X-Sendfile を受け持つ）を起動し、その後ろで `bin/rails server` を動かす | Rails 生成 |
| `bin/jobs` | Solid Queue の dispatcher・worker・scheduler を起動する。設定は `config/queue.yml` と `config/recurring.yml` | Solid Queue 生成（M7 で追加） |

### bin/docker-entrypoint で変えたこと

生成されたままの `bin/docker-entrypoint` は、コマンドが `./bin/rails server` なら、起動の前に `bin/rails db:prepare` を流す。本デモはこの分岐を消した。

DB のタスクには所有ロールの資格情報（`DB_OWNER_USER`・`DB_OWNER_PASSWORD`）が要る。所有ロールは `BYPASSRLS` を持つので、その資格情報を持つプロセスは RLS の外で全テナントを読み書きできる。そのため、デプロイの担当者は資格情報を Web のプロセスに渡さない。Web のコンテナで `db:prepare` を流すと、資格情報が無いので止まる。マイグレーションは、資格情報を渡した別の工程で `bin/rails db:prepare` を流す（[data-model.md「RLS」](../architecture/data-model.md#rls)）。

### bin/jobs が接続するロール

`bin/jobs` は `config/environment` を読み込むので、Web と同じくアプリのロールで接続する。ワーカーはテナントを設定せずにキューを読むので、Solid Queue の表には RLS を付けていない（[ADR 005](../adr/005-イベントのジョブをトランザクション内で登録する.md) 決定 5）。ジョブを実行するときは、`ApplicationJob` が投入した時のテナントを、イベントのジョブは宛先テナントを `Tenancy.with_tenant` で設定する。
