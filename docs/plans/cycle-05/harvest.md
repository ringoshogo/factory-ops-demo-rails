# サイクル 05 の知見の収穫

サイクル 05（M38・M39・M40・M33・M41）の実装で分かったことのうち、正本に無いものを正本へ書いた記録である。手順は `guides/cycle-end.md`「2. 知見の収穫」にある。逸脱検査（`conformance.md`）は、ここで足した正本を含めて成果物と突き合わせる。再発防止（`recurrence.md`）は、ここにある知見を 2 度書かない。

読んだものは、サイクルの diff（`git diff 0f84d5d..5c5d5cd`）、振り返りの想定外（`retrospective.md`）、台帳の `judgment` の行（OI-150〜OI-176）と改善の候補（IB-67〜IB-93）、実装レビューの証跡の「実装の記録」、正本（`architecture/`・`adr/`・`guides/`・`README.md`・`showcase.md`・`deploy/README.md`）である。diff の層ごとの読み取りは、取りまとめ役とも実装者とも別の Claude のサブエージェントに `5c5d5cd` の版で頼み、結果をファイルと行で確かめてから書いた。リポジトリを public にしたので、README と ADR が private を前提に書いた箇所も読んだ。arm64 の GitHub ホストのランナーが public のリポジトリで使えることは、GitHub の changelog（2025-08-07）で確かめた。マイルストーンの中で正本に書き足した分（`graphql-schema.md`「ページングと N+1」と SDL、`data-model.md` の状況の導出と公開の配置の監査ログ、`adr/009`・`adr/010`、`testing.md`「行列テストとの分担」、`config.md`「環境ごとの設定」「ジョブ」、`README.md`「構成」「画面」、`deploy/README.md`）は済んでいるので、ここではその漏れを拾った。

## 正本に書いた項目

| 層 | 項目 | 分類 | 正本の状態 | 書いた文書と節・内容 | 根拠 |
|---|---|---|---|---|---|
| CI と設定 | CI のジョブは 6 つ（`scan_ruby`・`lint`・`test`・`frontend`・`e2e`・`images`）で、`frontend`・`e2e`・`images` は `bin/` の検査を呼ばない | 手順 | 不正確。「3 つのジョブ」と書き、表に `frontend`・`e2e`・`images` が無かった | `guides/bin.md`「CI が使うもの」の表に 3 つのジョブを足した（再発防止で足した `image_inputs` も同じ表に書いた） | `48191bf`・`5dca71c` |
| CI と設定 | `images` のジョブ（マニフェストの照合とイメージの組み立て）は `bin/ci` に無く、手元では `kubectl kustomize deploy` と `deploy/README.md` の手順で確かめる | 手順 | 無い。画面の検査だけを書いていた | `guides/config.md`「CI の工程」 | `5dca71c` |
| 決定 | GHCR のパッケージの可視性はリポジトリと別に決まり、読み取りの Secret で取りに行く形はリポジトリを public にした後も変えない | 決定 | 不正確。「リポジトリが private の間はパッケージも private」と書いていた | `adr/009` 決定 6、`deploy/README.md`「Secret」の `ghcr-pull-secret` の行 | `5dca71c`・`7bbe572` |
| 決定 | arm64 の GitHub ホストのランナーは public のリポジトリで使える | 決定 | 不正確。見直す条件が「リポジトリが private の間に使えるかは移すときに確かめる」と書いていた | `adr/009`「見直す条件」の `images` の行。移すかは改善の探索で裁定する（IB-93） | `5dca71c` |
| 公開 API | シードは本番の環境では動かず、本番の環境で世界を作るのは `DEMO_WORLD_ENABLED=1` を渡した毎日の作り直しの工程だけ | 手順 | 不正確。README は「シードは本番の環境では動かない」とだけ書き、spec のコメントは「本番の環境では呼べない」のままだった（振り返りの逆向きの照合） | `README.md`「開発環境」、`packs/inventory/spec/public/inventory/stocks_spec.rb` のコメント | `5dca71c` |
| 公開 API | 受注・発注・出荷依頼の状況を SQL の式 1 つで導出し、一覧の表示・絞り込み・件数・ダッシュボードの件数が同じ式を読む | 作り方 | 不正確。見せどころは「時刻列から導出する」だけで、M40 の形と ADR 010 が無く、README の文書の表にも ADR 010 が無かった | `showcase.md`「3. 責務と関心の分離」、`README.md`「ドキュメント」 | `c38eea2`・`1f44023` |
| テスト | RLS に隠れる scope と所有の条件を、行列と単体の共有の文脈がテストの DB にだけポリシーを足して落とす | 作り方 | 無い。見せどころのテーマ 1 に M37・M38 の守りが無かった | `showcase.md`「1. テナントの境界：読む 3 経路、書けないこと、失効」 | `7b8e567`・`2439379` |
| GraphQL | すべての一覧が件数を持ち、画面の一覧は並べ替えと絞り込みをサーバーで行い、件数とページを同じ relation から引く | 作り方 | 無い。見せどころのテーマ 6 に M39・M40 が無かった | `showcase.md`「6. GraphQL の安全な形」 | `aafbb35`・`0fcd396`・`ea1e224` |
| テスト | 画面のテストは rspec の外にあり、URL の値を変数に写す関数と呼び出し口は Vitest の単体に、画面を通す流れと寸法・コントラスト・件数の一致は Playwright の E2E に置く | 作り方 | 無い。「テストの層」は rspec の置き場だけだった | `guides/testing.md`「テストの層」、`showcase.md`「8. 機械で守る規約」「9. テスト戦略」 | `6b91bbe`・`1867a56`・`fde0d5b` |
| テスト | S1 と S2 を画面でも通す E2E（テナントの切り替え、失効） | 作り方 | 無い。重要シナリオの表の置き場が rspec だけだった | `guides/testing.md`「重要シナリオ」の表 | `1867a56` |
| CI と設定 | 公開の配置のマニフェストと作り直しを spec と CI が守ること | 作り方 | 無い。見せどころのどのテーマにも `deploy/` と ADR 009 が無かった | `showcase.md`「10. 運用性」 | `5dca71c`・`844c291` |
| CI と設定 | `web`・`jobs`・`frontend` は `Recreate` で、適用のたびに画面が止まる | 手順 | 無い。理由はマニフェストのコメントにだけあり、作者の手順に止まる時間が無かった | `deploy/README.md`「2. 適用」 | `5dca71c` |
| テスト | E2E を強制終了すると、次の実行の準備が心拍のしきい値（5 分）を過ぎるまで止まる | 手順 | 無い。`frontend/playwright.config.ts` のコメントにだけあった | `README.md`「画面」 | `6b91bbe`・`fe3cc7b` |
| CI と設定 | README の流用元 `factory-ops-demo` は公開していない | 手順 | 無い。公開の読み手は流用元を開けない | `README.md` の冒頭 | `7bbe572` |

計画の M33 と M41 の節が「public にする時期はまだ決めない」と書いていた文は、台帳の棚卸しで、OI-06 の結果に合わせて直した（`inventory.md`）。

## 書かなかった項目

| 層 | 項目 | 理由 |
|---|---|---|
| 表とマイグレーション | サイクル 05 に表とマイグレーションの変更は無い。RLS の UPDATE のポリシーは spec の補助が足し外しするだけ | — |
| 公開 API | `Page` を作ったテナントの外で読むと例外にする、カーソルの値の範囲 | 正本にある（`graphql-schema.md`「ページングと N+1」、OI-153） |
| 公開 API | 状況の式の副問い合わせに scope を掛けず、出荷停止だけ所有テナントをそろえる、`SqlSubquery` で値を渡す | 正本にある（`adr/010` 決定 3、`data-model.md`「状態は保存せず、時刻列から導出する」、`graphql-schema.md`「1 回のリクエストがたどる道」3、OI-160） |
| ジョブとイベント | 出荷停止の解除の upsert で、他社の行に当たったら失敗させる | 正本にある（`testing.md`「行列テストとの分担」、OI-152） |
| テスト | 共有の文脈が UPDATE のポリシーも開く形と、届かない 3 つの形 | 正本にある（`testing.md`「行列テストとの分担」） |
| テスト | 公開 API でないジョブの `FOR UPDATE` の所有の条件 | 改善の候補 IB-71 にある |
| GraphQL | 入力型の形、`keyword` の全角の空白、予算の表の一覧を持たない文書と詳細の親 | 正本にある（`graphql-schema.md`「ページングと N+1」と SDL、OI-156・OI-157・OI-161） |
| GraphQL | `pageInfo` だけの写し、件数と行の時点、入れ子の `totalCount`、照合順序 | 改善の候補 IB-73〜IB-75・IB-77 にある |
| 画面 | ダッシュボードの KPI と一覧のタブのまとまり | 確信を持てない。作者の確認を待つ `judgment`（OI-164・OI-165）なので、確かめてから計画の M33 の画面の表か `context-map.md` に置く。次のサイクルへ送る |
| 画面 | Next のデータのキャッシュを使わない理由、Rails を 1 か所から呼ぶ、先読みしない `Link`、セキュリティのヘッダ、standalone の出力 | 実装の手段。`frontend/eslint.config.mjs`・`next.config.mjs` の規則とコメントから同じ意図を見つけ直せる。見せどころには規約として書いた |
| 画面 | 取り込みのファイルを route handler で送る、Node 22 と依存の版、画面のコメントの検査 | 正本にある（`guides/config.md`「CSRF を防ぐ前提：CORS を開けない」、`README.md`「画面」、`guides/comments.md`、OI-163・OI-167） |
| CI と設定 | `.rubocop.yml`・`packwerk.yml`・`.dockerignore` で `frontend/` を外す、dependabot に npm を足す | 実装の手段。各ファイルのコメントに理由がある |
| CI と設定 | `TEST_DATABASE`・`assume_ssl`・`DB_HOST`・`NOTIFICATIONS_PROVIDER`・`SHARED_DEMO_ACCOUNTS`・`DEMO_WORLD_ENABLED`・async のモード | 正本にある（`guides/config.md`「DB の接続」「環境ごとの設定」「ジョブ」） |
| CI と設定 | Rails の `db:prepare` は、同じプロセスで作り直した DB に構造を読み込まないので、子のプロセスか別のコマンドで流す | 実装の手段。`lib/tasks/e2e.rake` と `lib/demo_reset.rb` のコメントにあり、OI-168 にもある |
| CI と設定 | migrate の Job が `db:prepare` の後に `db:grant_app_role` を明示して流す | 確信を持てない。`db:prepare` に足し込んだ付与と重ねた理由が無く、要るかを確かめていない。次のサイクルへ送る |
| CI と設定 | `bin/rails demo:reset` を `guides/bin.md`「bin/rails で流す運用のタスク」に載せるか | 確信を持てない。作者は CronJob から Job を作って流し、rake タスクを直に流さない。表に載せると開発の DB で流す誤りを誘いうる（IB-90）。IB-90 と合わせて次のサイクルへ送る |
| CI と設定 | `images` のジョブの push をテストの成功に結ぶか、NetworkPolicy、手元の `demo:reset` を入口で止めるか | 改善の候補 IB-90〜IB-92 にある |
| CI と設定 | GitHub ホストの `ubuntu-latest` が 2026-10-19 から Ubuntu 26 に移る（CI の注釈） | 正本に書く知見ではない。CI の `test`・`e2e` は PGDG の `postgresql-client-18` を `lsb_release -cs` の名前で入れるので、移った後に入らないおそれがある。改善の候補 IB-94 に積んだ |
| 配置 | アドバイザリロック、終わった Pod を待たない、終了の猶予と API の時間切れ、Secret の名前、ホスト名を 1 か所に書く、公開の配置の監査ログ | 正本にある（`deploy/README.md`「作者が決める値」「Secret」「作り直しが途中で止まったとき」、`data-model.md`「監査ログ（`platform`）」）。値は実装の手段 |
| README | リポジトリにライセンスのファイルが無い | 確信を持てない。公開のリポジトリの利用条件は作者が決めることなので、作者への一覧に載せた（`inventory.md`） |
| README | 「開発環境」の `libpq` の道が macOS の Homebrew のもの | 書かない。行のコメントと続く段落が「pg_dump 18 を使う」ことを書いており、ほかの OS の読み手も読み替えられる |

## 見た層

| 層 | 見たもの | 書いた項目 |
|---|---|---|
| 表とマイグレーション | `db/` に diff が無いこと、spec の補助のポリシー | 無し |
| 公開 API | 受け手と公開 API の diff（出荷・在庫・購買・受注・取引関係）、`Page`・`SqlSubquery`・`DemoWorldGate`、状況のモジュール | シードと本番の環境、状況の導出 |
| policy | policy のファイルの diff は無い。scope の位置は公開 API と ADR 010 で見た | 無し |
| GraphQL | リゾルバと入力型、`base_connection.rb`・`paged_connection.rb`、`schema.graphql`、`graphql_operations.yml` | 一覧 |
| ジョブとイベント | 受け手の spec の diff、`lib/demo_reset.rb`・`lib/demo_reset/kubernetes.rb`、`lib/e2e_prepare.rb` と rake タスク | 無し |
| テスト | `spec/matrix`・`spec/support`・`spec/graphql/query_budget_spec.rb`・`spec/platform` の追加、`frontend/e2e` と `frontend/lib` の単体 | 共有の文脈、画面のテストの置き場、S1・S2 の画面、E2E の強制終了 |
| CI と設定 | ワークフロー、`config/ci.rb`、`application.rb`・`database.yml`・`production.rb`、`.rubocop.yml`・`packwerk.yml`・`.dockerignore`・dependabot、2 つの Dockerfile、`deploy/` | CI のジョブ、`images` と `bin/ci`、GHCR とランナー、適用の停止、配置の見せどころ |
| 画面 | `eslint.config.mjs`・`next.config.mjs`・`security-headers.json`・`package.json`、README「画面」 | 画面の規約の見せどころ |
| 公開の前提 | README・ADR・`deploy/README.md`・`handoff.md` の private と流用元への参照 | GHCR、流用元 |
