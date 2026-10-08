# 引き継ぎ：作業の現在地と次の一手

新しいセッションで作業を再開する人（Claude を含む）が最初に読む文書。プロジェクトの目的、決まったこと、決まっていないこと、次にやることを示す。

## 目的

このリポジトリは、作者が Rails のアーキテクトとして設計判断できることを示すポートフォリオである。見せたいのは動く機能の多さではない。設計判断（`architecture/decisions.md`）が、コードのどこで、どの仕組みで守られているかを読み手が辿れることである。

実装の優先順位はこの目的で決める。見せどころの一覧は `showcase.md` にある。

一方、フロントエンドは見せどころではない。姉妹プロジェクト `factory-ops-demo` の Next.js を流用し、データ取得層だけを GraphQL に書き換える。

## 読む順

1. `../README.md`：構成の要約
2. `showcase.md`：見せどころ。何を示したいかと、それを守るコード・テスト・実装の状態
3. `architecture/context-map.md`：業務の流れと 6 つのコンテキスト、つなぎ方、品番照合・取消・検収と請求の流れ、取引関係の失効、許可する依存の向き、テナントの所有
4. `architecture/data-model.md`：テナントの持ち方、状態の導出、各コンテキストのテーブル、取消と出荷の競合の止め方、イベントの冪等キー、RLS
5. `architecture/graphql-schema.md`：GraphQL の型を視点ごとに分ける形、相手側へたどれないことの保証、認可の基底クラス、クエリと mutation が呼ぶ公開 API
6. `architecture/decisions.md`：設計判断の一般原則。各論点の既定の推奨と裏返る条件
7. `adr/`：本デモで下した個別の判断
8. `implementation-plan.md`：実装の順番。マイルストーンの一覧と、各マイルストーンの完了条件。実装を始める人は、着手するマイルストーンの節と、そこが挙げる設計文書の節を読む
9. `guides/`（必要なときに）：`bin/`・`config/`・`packs/` と packwerk の解説。Rails の生成物から何を変えたか、packwerk の違反をどう読んで直すかを知りたいときに読む背景。コードにコメントを書く人は、`guides/comments.md` を先に読む

`decisions.md` は一般論で、完全分離型のマルチテナントも扱う。本デモに当てはめた結果は `context-map.md`・`data-model.md`・`graphql-schema.md`・`adr/` にある。両者が食い違う場合は `adr/` が優先する。

## 決まったこと

| 項目 | 決定 | 根拠 |
|---|---|---|
| 題材 | factory-ops-demo と同じく、架空の機械部品メーカー「青嵐精機工業」の受発注・在庫管理 | ユーザー判断 |
| マルチテナント | 相互アクセス型。発注側と受注側が同じシステムを使い、発注が相手の受注に連結する | ユーザー判断、`context-map.md` |
| コンテキスト | 取引関係・購買・受注・在庫・出荷・請求の 6 つ＋イベント置き場 `contracts` | `context-map.md` |
| 発注側からの取消 | 可能。受注側の承認が要る。審査の間は出荷を止める | ユーザー判断、`context-map.md`「取消の流れ」 |
| 品番 | 発注側は自社品番で発注する。受注側の腐敗防止層が対応表で読み替える | ユーザー判断、`context-map.md`「発注の連結と品番の照合」 |
| 検収と請求 | 検収の結果を「検収完了」で受注側へ返す。受注側が検収数量 × 受注単価で取引先ごとに月次で締めて請求書を発行し、発注側は「請求書発行」で届いた写しを閲覧する。入金消込は範囲外 | ユーザー判断、`context-map.md`「検収と請求の流れ」 |
| 取引関係の失効 | 読む 3 経路と新しい発注は閉じる。「発注登録」を出し終えた取引は請求まで進む | ユーザー判断、`context-map.md`「取引関係の失効」 |
| 構成 | Rails（API モード）＋PostgreSQL＋GraphQL。フロントは factory-ops-demo の Next.js を流用 | ユーザー判断 |
| スキーマ管理 | Rails マイグレーション＋`structure.sql`。ridgepole は使わない | `adr/001` |
| 主キー | UUIDv7 を DB の `uuidv7()` で作る。PostgreSQL 18 以降を使う | `adr/003` |
| データモデル | 全テーブルに `owner_tenant_id`、親子は複合外部キー、状態は時刻列から導出、引当は在庫だけが持つ。RLS の `WITH CHECK` は全表で所有テナントに限り、読む 3 経路にだけ SELECT のポリシーを足す | `architecture/data-model.md` |
| DB ロール | 所有ロール `factory_owner`（表の所有者、`BYPASSRLS`）とアプリのロール `factory_app`（一般ロール）に分ける。アプリ・テスト・ワーカーは `factory_app` で接続し、権限は DB のタスクの後に rake タスクで付与する。`tenants` への書き込みは追加だけを許す。本番では所有ロールの資格情報をマイグレーションの工程にだけ渡し、Web とワーカーには渡さない | `implementation-plan.md` M3、`architecture/data-model.md`「RLS」 |
| 境界の強制 | 初日から `packs/` 構成。packwerk の依存チェックとプライバシーチェックを CI で強制する | ユーザー判断、`adr/002` |
| イベントの配送 | Solid Queue を業務 DB と同じ接続に置き、イベントのジョブは業務のトランザクションの中で登録する（`Contracts::EventJob` は `enqueue_after_transaction_commit = false`、それ以外の `ApplicationJob` は `true`）。outbox は置かない。登録は `Contracts.publish` が配送表 `Contracts::Subscriptions` の受け手ごとに行い、受け手は宛先テナントの名義で冪等に処理する。キューの接続が同じであることをテストで固定する | `adr/005` |
| テスト | RSpec＋FactoryBot。設計文書がガードテストを `spec/` のパスで定めているため | `implementation-plan.md`「環境」 |
| 基盤パッケージ | `packs/platform` を足し、`ApplicationRecord`・`ApplicationJob`・`Current`・`Tenancy` を置く。基底クラスをルートパッケージに置くと、パッケージからルートへの依存が循環になるため | `implementation-plan.md` M2 |
| GraphQL | graphql-ruby と Action Policy。1 つのスキーマで `buyer`・`supplier` の入口を分け、型に視点を宣言させて到達可能性をテストで固定する。汎用の `node` は置かない。基底の型・リゾルバ・mutation は宣言が無ければ拒否する | `architecture/graphql-schema.md`、`adr/004` |
| マイルストーンの順 | 残りの業務機能（M21〜M26）の前に、横断の仕組み（M15〜M20：コメントの規約・テストの層・N+1 の検出・構造化ログ・監査ログ・スキーマの差分検査）を入れる。見せどころ（M27〜M31：バイテンポラル・非同期の型・取り込み・メトリクス・SLO）は業務機能の後に足す | `implementation-plan.md`「マイルストーンの一覧」 |
| 販売単価 | 有効期間（`daterange`）と記録期間（`tstzrange`）の 2 軸で持つ。現在の行の有効期間の重なりを排他制約で止め、行は書き換えない。受注は受注日の単価を写す | `adr/006` |
| 非同期処理の型 | ジョブを失ったときに誰も気づけない処理だけを、トランザクションの中で登録する。型は記録してから処理する A-1 イベント・A-2 確実な外部送信・A-3 inbox・A-4 再開できる長時間のジョブと、記録しない B-1 撃ちっぱなし。外部への作用の重複は C-1〜C-3 から選ぶ。outbox は置かない。外部への作用は `ExternalEffectJob` を継承し、登録口を 1 つにする。テストと開発で本物の SendGrid を呼ばない | `adr/007` |
| ログ | `Rails.event` を出口にした 1 行 1 件の JSON。相関 ID と因果 ID をイベントの付帯情報で運び、テナントをまたぐ一連の処理を引けるようにする。ペイロードに個人情報と自由記述を入れない | `implementation-plan.md` M18 |
| 監査ログ | 相手テナントに効果が及ぶ書き込みを、mutation とイベントのジョブの基底クラスが記録する。追記だけで、自社の `admin` が `viewer.auditLogs` で読む | `implementation-plan.md` M19、`architecture/data-model.md`「監査ログ（`platform`）」 |
| テストの層とシナリオ | 単体を厚くし、層ごとの件数を CI で報告する。壊れると事故になる 5 つの流れ（S1〜S5）を、専用のシナリオテストにする。N+1 は Bullet とクエリ数の予算で落とす | `implementation-plan.md` M16・M17 |
| GraphQL のスキーマの変更 | `schema.graphql` を commit し、非推奨を経ない破壊的変更を CI で落とす | `architecture/graphql-schema.md`「スキーマの変更と非推奨」 |
| メトリクス | Yabeda と Prometheus。値は `Rails.event` から作り、ラベルにテナントとユーザーを入れない | `implementation-plan.md` M30 |
| コードのコメント | いまの振る舞いと理由だけを書き、経緯・マイルストーンの番号・予定を書かない。Cop で止める | `guides/comments.md` |
| 拡張の進め方 | 横断の仕組み（M15〜M20）を業務の残り（M21〜M26）より先に入れる。監査ログの保存期間（7 年）と SLO の値は仮置きのまま進め、値より決め方と測り方を示す。発注側に単価の改定予定は見せない。取り込みは失敗した行だけを報告し、正常な行は反映する | ユーザー判断、`implementation-plan.md` |

## 決まっていないこと

- **GitHub リポジトリを public にする時期**：いまは private。仕上がってから切り替える
- **横断の仕組みを業務機能の残りより先に入れる順**：M15〜M20 の分だけ、取消・検収・請求の実装が後ろへずれる。業務機能を先に通したいなら、M19（監査ログ）と M20（スキーマの差分検査）だけを先にし、残りを M26 の後へ回す案がある
- **監査ログの保存期間**：7 年で仮に置いた（`architecture/data-model.md`「監査ログ（`platform`）」）
- **SLO の値**：`implementation-plan.md` M31 の値は初めの目安で、実測の後に見直す
- **発注側に単価の改定の予定を見せるか**：いまは今日の単価だけを見せる。見せるなら、経路 1 の型にフィールドが増える（`adr/006` 決定 7）
- **取り込みで失敗した行があるときの扱い**：行ごとに独立に反映し、失敗した行だけを報告する（`implementation-plan.md` M29 の判断）。全部か無しかを求めるなら、方式を変える

## 次にやること

再開する人は、次の順に進める。

1. **M11〜M14 をレビューする**：M3・M4〜M7・M8〜M10 は、読み取り専用のレビューを通して指摘を直した。M11〜M14 はレビューを途中で止めたので、まだ通していない。見る観点は、在庫の不変条件、ロック順とデッドロック、引当の消費と解除の競合、出荷停止中の計上、受け手の同時重複配送、新しいフィールドからの漏れである。
2. **M14 の残り**：受注の scope にある自社テナントの条件は RLS と重なっており、単独で効いていることをテストで示せていない。
3. **全テーブルに日本語 1 行の説明を付ける**：`COMMENT ON TABLE` を足すマイグレーションを書き、`structure.sql` と psql の `\dt+` で読めるようにする。説明の先頭にコンテキスト名（`[受注]` など。コンテキストに属さない表は `[基盤]`・`[キュー]`）を付け、コンテキストごとに一覧できるようにする。説明の無い表があれば落ちる spec も足す。DB のスキーマをコンテキストごとに分ける案は、RLS・packwerk・マイグレーションへの影響が大きいので採らない。接頭辞で足りるかは、着手時に作者に確かめる。
4. **M15 から M32 まで、`implementation-plan.md` の順に実装する**：横断の仕組み（M15〜M20）、業務機能の残り（M21〜M26）、見せどころ（M27〜M31）、シード（M32）の順である。M33（フロントエンド）は範囲外のまま。計画を広げたときに M15 以降の番号を付け直したので、コードに残っている `M15`・`M17` は古い番号を指す。M15 のコメントの掃除で消す。

各段階で決めたことは、`adr/`・`context-map.md`・`data-model.md`・`graphql-schema.md` のいずれかに残す。

### 1 つのマイルストーンの回し方

- **ブランチと PR**：マイルストーンごとに、前のマイルストーンのブランチから `mNN-...` を切り、前のブランチを base にした PR を作る（PR を積み重ねる）。main への直接 push はフックが拒否し、PR のマージは作者が行う。積み重ねた PR は、前から順に、base を main へ付け替えてからマージコミットでマージする。途中でブランチを消すと、それを base にしていた PR が閉じられるので、ブランチは全部マージしてから消す。
- **完了の判定**：`implementation-plan.md` の完了条件に加え、rspec・rubocop・`bin/packwerk check`・brakeman・`bin/check-structure`（migrate と load の両経路で `structure.sql` が一致すること）を通す。M16 以降は `bin/test-layers`、M20 以降は `bin/check-schema-compat` も通す。守りの検査は、外すとテストが落ちることを確かめてから戻す。
- **レビュー**：3 マイルストーン前後ごとに、読み取り専用のレビューを別の worktree で行う。Critical・High・Medium は、そのマイルストーンのブランチに修正の commit を積み、後ろのブランチを rebase する。

### 開発環境

- `export PATH="$HOME/.rbenv/shims:/opt/homebrew/opt/libpq/bin:$PATH"`（Ruby 3.3.3、pg_dump 18）
- DB は `docker compose up -d --wait`（PostgreSQL 18、ポート 5433）
- rspec の全件は 2 分を超える。テストを並行して流すときは、別名の一時 DB を使う
- GitHub の操作（push・PR）の前に `gh auth switch -u ringoshogo` で個人アカウントへ切り替える。gh の既定は仕事用の `ringo-shg` で、そのままでは push できない

## リポジトリの状態

- **このリポジトリ**：リモートは GitHub の `ringoshogo/factory-ops-demo-rails`（private）。git の作者も ringoshogo にする。
- **ブランチ**：M1〜M14 は main にマージ済み。Dependabot の依存更新の PR が 3 本、未処理で残っている。
- **実装**：M14 まで終えた。rspec は 840 examples, 0 failures。`implementation-plan.md` のマイルストーンを終えるたびに、ここへ書く。
- **親のモノレポ（`shogo-project`）**：`.gitignore` に `/factory-ops-demo-rails/` を追加し、README の「別リポジトリで管理しているもの」の表に行を足した。どちらも未 commit である。

## 持ち込まなかったもの

`decisions.md` は、作者の勤務先で行った 3 者の討論（Rails Way 派・構造化派・Codex）の結論である。討論の原文と、根拠として添えていた勤務先コードの観察は、社内のコードを含むため持ち込んでいない。勤務先のコード・社名・顧客名は、このリポジトリに書かない。
