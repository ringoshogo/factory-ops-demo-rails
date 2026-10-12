# factory-ops-demo-rails

Rails で B2B SaaS を 0 から作るときの設計判断を、実際に動くアプリとして示すデモ。設計の決定事項（`docs/architecture/decisions.md`）を正本とし、各判断がコードのどこで機械的に守られているかを辿れるようにする。

何を見せたいか、どこから見ればよいかは [`docs/showcase.md`](docs/showcase.md) にまとめた。初めて読む人は、その「全体の流れ」から始める。

題材は姉妹プロジェクト `factory-ops-demo`（Go＋Next.js）と同じく、架空の機械部品メーカーの受発注・在庫管理である。本デモはこれに請求を加える。もう 1 つの違いはマルチテナントにあり、本デモは **相互アクセス型**（取引関係にあるテナント同士が、相手のデータの一部を参照・操作する）を採る。決定事項の文書は完全分離型も扱うが、本デモでは相互アクセス型に関わる判断を実装の対象にする。

> 本リポジトリのデータ・企業名はすべて架空で、実在の企業・業務データとは関係ない。

## 構成

- **バックエンド**：Rails（API モード）＋ PostgreSQL
- **API**：GraphQL
- **フロントエンド**：`frontend/` の Next.js。factory-ops-demo の画面部品を写し、データ取得層を GraphQL に替え、発注側の画面を足した。ブラウザは Next のサーバーだけを呼び、Next のサーバーが Rails を呼ぶ。起動の手順は「画面」にある
- **認可**：DB の RLS（自社の行と、相手を読む 3 経路の粗い条件）、Action Policy の scope（公開 API が返す行の絞り込み）、Action Policy の規則（操作ごとの許否と役割）の 3 段で分担する。どのデータにも 3 段が順に掛かる（`docs/architecture/graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
- **配置**：`deploy/` の Kustomize のマニフェストで、流用元と同じ Raspberry Pi の k3s に Rails・ジョブのワーカー・Next・PostgreSQL を置き、画面だけを Cloudflare Tunnel で公開する。全員が同じデモのデータを使い、毎日シードから作り直す。イメージは CI が arm64 で作る。作者が実機で行う手順と Secret の入れ方は `deploy/README.md` にある
- **コードの置き場**：業務のコードは、コンテキストごとに `packs/<パッケージ>/app/` に置く。他のパッケージから呼べるのは `app/public/` の下だけで、依存してよい先は各 `package.yml` に書く。どちらも `bin/packwerk check` が CI で検査する。Rails の基底クラスは `packs/platform` にある

## 開発環境

開発者は、手元で最初に次を実行する。DB は `compose.yaml` の PostgreSQL 18 をポート 5433 で立てる。

```sh
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"   # pg_dump 18（brew install libpq）
bin/setup --skip-server
bundle exec rspec
```

DB には 2 つのロールで接続する。アプリとテストは RLS が掛かる `factory_app`、DB のタスクは表の所有者の `factory_owner` を使い、どちらも `bin/setup` が作る（`docs/architecture/data-model.md`「RLS」）。本番で所有ロールの資格情報を渡す工程も、同じ節にある。

pg_dump は 18 系を使う。18 未満の pg_dump は 18 のサーバーに対して動かず、`db/structure.sql` を書けないため、`bin/setup` は 18 未満なら止まる。Ruby は `.ruby-version` の版を rbenv で入れる。この版にする理由は、`Dockerfile` の `RUBY_VERSION` の直前のコメントにある。

画面や API を手で触る開発者は、次でデモのデータ（シード）を作る。受注側の青嵐精機工業と、発注側の架空の組立メーカー 2 社（東海産機システムは全権限の付与あり、北関東オートメーションは失効済み）と、各社の `admin` と `member` のユーザー、品目・在庫・取引・請求書・取り込みができる。

```sh
bin/rails db:reset   # DB を作り直してシードを流す。DB が空なら bin/rails db:seed だけでよい
bin/jobs             # 通知のメールを送る（開発の送信先は tmp/mails/）
bin/rails server
```

シードを流す間は `bin/jobs` を止めておく。シードはジョブを自分で流すので、ワーカーが同時に動くと、同じジョブを両方が動かすことがある。受け手は冪等なので結果は変わらないが、ジョブの記録が重なる。ログインに使うアカウント（メールアドレスと、共通のパスワード）は `db/seeds/demo_accounts.json` にあり、シードの終わりにも表示する。パスワードはデモの手元で使う値で、本番の資格情報ではない。シードは同じ DB で 2 回目を流しても何も作らない。受注側のテナントがあれば、世界ができていると見なすからである。そのため、シードが途中で失敗したら、`bin/rails db:reset` から流し直す。シードは本番の環境では動かない。

シードは `DemoWorld`（`lib/demo_world.rb`）が作る。E2E の世界も、同じ `DemoWorld` で `namespace` を変えて同じ DB に作るので、シードの中身を変えるときは `DemoWorld` を直す。`DemoWorld` は公開 API とイベントだけで世界を作り、業務の表へ直接書かない。`admin` に限る操作は、mutation と同じ規則を評価してから呼ぶ（`docs/architecture/graphql-schema.md`「役割による制限」）。各段の後に、イベントと取り込みのジョブをその場で流すので、`bin/jobs` を起こさなくても取引は進む。業務の日付（発注日・受注日・検収日・請求書の発行日）はシードを流した日になり、希望納期・出荷日・出荷指示の予定日・単価の改定日・締め日（月末）だけが、今日から決めた値になる。

## 画面

画面を手で触る開発者は、「開発環境」のシードを流して Rails を起こしてから、別の端末で `frontend/` の Next を起こす。Node は `frontend/package.json` の `engines` の版（22 系）を使う。

```sh
cd frontend
npm ci
npm run dev          # http://localhost:3001。Rails は RAILS_URL（既定 http://127.0.0.1:3000）を呼ぶ
```

`http://localhost:3001` を開き、ログインの画面に並ぶシードのアカウントを押してログインする。Rails の取り込みのファイルの受け口は、ブラウザの `Origin` を `FRONTEND_ORIGIN`（既定 `http://localhost:3001`）と比べるので、`127.0.0.1` ではなく `localhost` で開く。

画面の検査は次で流す。`codegen:check` は、根の `schema.graphql` と `frontend/graphql/` の画面の問い合わせから型を作り直し、`lib/graphql/generated.ts` と一致することを確かめる。スキーマか画面の問い合わせを変えたら `npm run codegen` で作り直して commit する。

```sh
cd frontend
npm run codegen:check && npm run lint && npm run typecheck && npm run test:unit
PLAYWRIGHT_CHANNEL=chrome npm run test:e2e   # 手元の Chrome で流す。CI は Playwright の chromium を入れて流す
```

E2E は、Playwright が E2E の DB（`factory_ops_e2e`）を作り直してワーカーごとに世界を作り、Rails（3200）・`bin/jobs`・Next（3201）と、Rails に届かない Next（3202）を起こす（`frontend/e2e/start-rails.sh`）。手元の開発のサーバーとはポートと DB が別なので、動かしたまま流せる。rspec とは同時に流さない。E2E の Rails も test の環境で `log/` のファイルに書き、ログの spec（`spec/platform/logging_spec.rb`）がそのファイルの末尾を読むからである。検収表のスクリーンショットは `E2E_SCREENSHOTS=1` を付けて流すと `frontend/test-results/acceptance/` に撮る。

## ドキュメント

| ファイル | 内容 |
|---|---|
| `docs/showcase.md` | 見せどころ。全体の流れ（題材・壊れやすい 4 つの点・守り方と証拠）と、テーマごとの設計判断・守っているコード・確かめるコマンド・実装の状態 |
| `docs/handoff.md` | 引き継ぎ。作業の現在地、決まったこと・決まっていないこと、次にやること。再開時に最初に読む |
| `docs/architecture/decisions.md` | 設計の決定事項。最初の 1 か月で決める順と、各論点の「既定の推奨・裏返る条件・撤退コスト」 |
| `docs/architecture/context-map.md` | コンテキストマップ。6 つのコンテキスト（取引関係・購買・受注・在庫・出荷・請求）と、その間のつなぎ方・テナントの所有・自社の中の役割 |
| `docs/architecture/data-model.md` | データモデル。テナントの持ち方、各コンテキストのテーブル、イベントの冪等キー、RLS ポリシー |
| `docs/architecture/graphql-schema.md` | GraphQL スキーマ。発注側と受注側の視点の型、相手側へたどれないことの保証、認可の基底クラス、クエリと mutation が呼ぶ公開 API |
| `docs/implementation-plan.md` | 実装計画。骨組みから業務機能までのマイルストーンと、各マイルストーンが機械で守るようにする規則・完了条件 |
| `docs/guides/bin.md` | `bin/` の各スクリプトの役割。誰がいつ流すか、Rails の生成物から何を変えたか |
| `docs/guides/config.md` | `config/` の各ファイルの役割。生成のままか変えたかと、変えた理由 |
| `docs/guides/packs-and-packwerk.md` | `packs/` 構成と packwerk の入門。2 つの検査、CI で落ちる場所、パッケージ・依存・公開 API を足す手順 |
| `docs/guides/dev-cycle.md` | 開発の回し方。サイクル・計画レビュー・実装レビュー・サイクル末の段階・残件の台帳と、文書の置き場の振り分け |
| `docs/guides/cycle-end.md` | サイクル末の 5 つの段階（振り返り・知見の収穫・逸脱検査・再発防止・台帳の棚卸し）と改善の探索の手順。各段階で読むもの・出すもの・終えてよい条件 |
| `docs/slo.md` | SLO と警報。6 つの SLO の値、誤差の予算の消費と状態の警報が何を測るか、値の見直し方 |
| `docs/runbooks/` | 警報ごとの手順書。警報を受けた人が、確かめること・止血・復旧・事後の順に読む |
| `deploy/README.md` | 公開の配置。置くもの、作者が決める値、Secret、作者が実機で行う手順、作り直しが途中で止まったときの戻し方 |
| `docs/plans/open-items.md` | 残件の台帳。その場で片付けず、決まったマイルストーンまでに決着させる事項の正本 |
| `docs/plans/improvement-backlog.md` | 改善の候補の台帳。期限は無いが、いまのやり方より良くできるかもしれない事項と、その裁定の記録 |
| `docs/guides/comments.md` | コードのコメントの規約。いまの振る舞いと理由だけを書き、経緯・マイルストーンの番号・予定を書かない。良い例と悪い例 |
| `docs/guides/testing.md` | テストの層と置き場、層への配分、競合テストの書き方、重要シナリオ S1〜S5 |
| `docs/adr/001-スキーマ管理にridgepoleを採用しない.md` | スキーマ管理に Rails マイグレーション＋`structure.sql` を選ぶ理由 |
| `docs/adr/002-packwerkを初日からCIで強制する.md` | `packs/` 構成と packwerk の依存・プライバシーチェックを初日から CI で強制する理由 |
| `docs/adr/003-主キーにUUIDv7を使う.md` | 主キーを UUIDv7 にし、DB で生成する理由 |
| `docs/adr/004-GraphQLの型を視点ごとに分けnodeを置かない.md` | 1 つのスキーマで型を視点ごとに分け、汎用の `node` を置かない理由 |
| `docs/adr/005-イベントのジョブをトランザクション内で登録する.md` | Solid Queue を業務 DB と同じ接続に置き、イベントのジョブを業務のトランザクションの中で登録する理由 |
| `docs/adr/006-販売単価を有効期間と記録期間の2軸で持つ.md` | 販売単価を有効期間と記録期間のバイテンポラルな行で持ち、行を書き換えない理由 |
| `docs/adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md` | 非同期処理を、記録してから処理する型（A-1〜A-4）と記録しない型（B-1）に分け、外部への作用の重複の扱い（C-1〜C-3）と合わせて、登録の時機・再試行・冪等・失敗の扱いを型ごとに決める理由。外部サービス（SendGrid）の呼び出しと Webhook の受信を含む |
| `docs/adr/008-本番に残すログの購読とミドルウェアを許した一覧で守る.md` | 値を文字列で書くフレームワークのログの経路を実行時には名指しで止め、本番の環境に残る購読とミドルウェアの並びを許した一覧との一致で spec が守る理由 |
| `docs/adr/009-デモを流用元と同じRaspberryPiのk3sに置き共有のデータを毎日作り直す.md` | デモを流用元と同じ Raspberry Pi の k3s に置き、画面だけを公開し、共有のデータを Web とワーカーを止めてから DB ごと毎日作り直す理由 |

## 状態

現在地は `docs/handoff.md` を見る。
