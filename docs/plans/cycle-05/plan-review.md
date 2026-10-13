# サイクル 05 の計画レビュー：M38・M39・M40・M33・M41 への反映

この文書は、`implementation-plan.md` の M38・M39・M40・M33・M41 を 2 系統の独立したレビュー（Claude と Codex）にかけ、指摘を計画に反映した記録である。M38 から M41 に着手する担当者と、計画をレビューする人が読む。担当者は、計画の節が「なぜこう書いてあるか」をここで引ける。

作者が M33 の著者判断を決めた（OI-06〜OI-14、`plans/cycle-05/m33-author-decisions.md`）。一覧の読み方（OI-07）を「全件を読み切って画面で並べる」から「サーバーで並べ替え・絞り込み・件数を出し、画面は 1 ページずつ読む」に、公開の配置（OI-14）を「作らない」から「流用元と同じ Raspberry Pi の k3s に置き、共有のデータを毎日作り直す」に変えた。取りまとめ役は、これを受けて M33 を 4 つに分けた。一覧の件数と並べ替えと列での絞り込みを M39、状況での絞り込みを M40、画面を M33、配置を M41 とし、配置の判断を `adr/009` に書いた（`11c38bf`）。M38 は、サイクル 04 の改善の探索で起こした節のまま出した。

初回のレビューは `11c38bf` を読んだ。依頼には読む版の commit を書いた。どちらの系統も No-Go で、Codex は M40 の境界、Claude は M41 の 4 つの High を、もう一度判定が要るものとした。High を直した版（`fd0b980`）を 2 系統で読み直し（読み直し 1）、どちらも Go だった。読み直しで出た Medium 以下と違和感は、読み直しには出さずに直した。Claude のサブエージェントは、初回も読み直しも最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ（`guides/dev-cycle.md`「独立したレビュアー」）。Codex は一時の失敗を起こさず、出し直していない。

読む順は、マイルストーンの分け方 → マイルストーンごとの判定 → 指摘ごとの対応 → 指摘の根拠を確かめた結果 → 作者の判断を待つ行 → 直さなかった指摘と台帳に積んだもの、である。指摘の出典は次の形で示す。2 系統の ID がぶつかるときは、`Codex M41-1` のように系統を添える。

| | Claude | Codex |
|---|---|---|
| 初回 | `<マイルストーン>-<番号>`（`M41-1` など） | `<マイルストーン>-<番号>` |
| 読み直し 1 | 違和感の番号 | 違和感の番号 |

## マイルストーンの分け方

| マイルストーン | 中身 | 分けた理由 |
|---|---|---|
| M39 一覧の件数と並べ替え、列での絞り込み | `Page` の組のカーソル、全コネクションの `totalCount`、6 つの一覧の `orderBy` と列の `filter`、`supplier.item(id:)`・`viewer.tenant`（OI-12） | 画面より先に API がそろわないと、画面が 1 ページずつ読めない。行列・S1・予算の検査を API の変更と同じ PR で直す |
| M40 状況での絞り込み | 状況の導出を SQL の式 1 つにし、3 つの一覧の `statuses` とダッシュボードの件数が同じ式を読む | 状況は導出した値で、列の絞り込みと作り方が違う。3 つのパッケージの導出を書き直すので、M39 から分けた |
| M33 フロントエンド | 画面の写しと GraphQL への書き換え。一覧は 1 ページずつ読む | 画面の範囲はサイクル 04 までの計画のまま |
| M41 Raspberry Pi の k3s への配置 | arm64 のイメージ、Kustomize のマニフェスト、毎日の作り直し、作者の実機の手順 | 実機でしか確かめられない部分を、spec で確かめる部分と分けて持つ |

サイクル 05 は M38・M39・M40・M33・M41 の 5 つで、1 つのサイクルの上限（6 つ）に収まる（`guides/dev-cycle.md`「全体の流れ」）。

## 判定

| マイルストーン | 初回 Claude | 初回 Codex | 読み直し 1 Claude | 読み直し 1 Codex |
|---|---|---|---|---|
| M38 RLS の UPDATE のポリシーが隠す所有の条件を、単体で捕まえる | Go | Go | Go | Go |
| M39 一覧の件数と並べ替え、列での絞り込み | Go | Go | Go | Go |
| M40 状況での絞り込み | Conditional Go | No-Go | Go | Go |
| M33 フロントエンド | Conditional Go | Go | Go | Go |
| M41 Raspberry Pi の k3s への配置 | No-Go | Conditional Go | Go | Go |

全体の判定は、初回は 2 系統とも No-Go だった。Claude は High を 6 件（M40 に 1 件、M33 に 1 件、M41 に 4 件）、Codex は High を 3 件（M40 に 1 件、M41 に 2 件）挙げた。Codex の M40 の判定（High 1 件で No-Go）と、Claude の M40 の判定（High 1 件で Conditional Go）は、同じ指摘への判定が割れたもので、境界の設計を変える直しなので No-Go を採り、読み直しに出した。

2 系統が同じことを挙げた指摘は次の 3 つである。

- 在庫の公開 API が AR の relation を返す案が、「公開 API は値を返す」規則と `adr/002` と食い違う（Claude M40-1、Codex M40-1。どちらも High）
- `daily-reset` の Role が Pod を読めず、「Pod が無くなるまで待つ」ができない（Claude M41-6 は Medium、Codex M41-1 は High）
- async のモードで、全ワーカーが分け合う DB の接続プールの大きさが決まっていない（Claude M41-5 は Medium、Codex M41-2 は High）

片方だけが挙げた High は次のとおりである。

- Claude だけ：かんばんの 7 列を `first: 10` で予算の表に書くと、いまの予算の spec が通らない（M33-1。Codex は同じ指摘を Medium にした）、本番の環境の `Secure` の Cookie を http で呼ぶ Rails が書かない（M41-1）、本番の環境で止めているシードの公開 API が 3 つある（M41-2）、毎日 DB ごと消すことと監査ログの保存期間（M41-3）、共有のアカウントのログアウトがほかの訪問者を切る（M41-4）

読み直し 1 は、前の High が解消したかと、High 以上の新しい指摘だけで判定した。2 系統とも、前の High 8 件をすべて解消と判定し、新しい High 以上は無かった。読み直しは High が出たときだけ続けると決めているので、読み直し 2 は回していない。M38 から着手できる。

## 指摘と対応

重大度は、2 系統で違うときは高い方を採った。「直した節」は、断りが無ければ `implementation-plan.md` の節である。各表は、初回の指摘、読み直しの指摘の順に並べる。

### M38

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Claude M38-1 | Medium | 対照を所有ロールの接続で読むと、example のトランザクションの中の行も書き込みも見えない | 作るもの 3。`cross_read!` で開いたまま同じ接続で他社の行を読み直す形にし、所有ロールの接続が見えない理由（`use_transactional_fixtures`）を書いた |
| Claude M38-2・Codex M38-1 | Medium | 完了条件のコマンドに `<作るもの 3 で集めた箇所の単体の spec>` の置き換えが残り、最初に落とす spec のパスも無い | 完了条件。操作者のいない入口の 4 つの公開 API の spec と、イベントの受け手の spec（`packs/*/spec/public/*/*_event_receiver_spec.rb`）をコマンドに書き、ほかに集めた箇所は足して証跡に書くとした。最初に落とすのを `spec/matrix/cross_read_spec.rb` の `pg_policies` の確かめにした |

### M39

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Codex M39-1 | Medium | カーソルに並べ替えの向きが無く、同じ列の `ASC` のカーソルを `DESC` に渡しても拒めない | 作るもの 1。カーソルに向きを持たせ、列か向きの違うカーソルを拒むとした。壊して落ちる記録に、向きだけを変えたカーソルを拒む example を足した |
| Claude M39-1 | Medium | 値の無い行がページの境目をまたぐ場合の確かめが無い。キーセットの条件が、カーソルの値が空のときと別になる | 作るもの 1 と完了条件。値のある行の後ろと、値の無い行の後ろの条件を別に書くとし、最初に落とす example を、値が同じ 3 行と値の無い 2 行を `ASC` と `DESC` の両方で境目にまたがせる形にした |
| Claude M39-2 | Medium | 並べ替えの列を一覧の表に限る判断は、作者の判断（OI-07）を狭めるので作者に見せるべき | OI-144 を `judgment` から `blocked-user` にし、引当先を、画面が並べ替えの見出しを決める M33 にした。M39 の判断の裏返る条件と、M33 の著者判断の節から OI-144 を指した |
| Claude M39-4 | Low | 並べ替えから `id` を外しても、行列の 2 回目の比較は確実には落ちない | 完了条件の壊して落ちる記録。`id` を外して落ちるのを `page_spec.rb` の境目の example だけにした |
| Claude M39-5 | Low | `totalCount` だけを選ぶ別名の一覧でも、ページの行と値への写しを読むかが決まっていない | 作るもの 2 と 7。`nodes`・`edges`・`pageInfo` を選ばなければページを読まないとし、予算の spec にその SQL の件数を確かめる example を足した |

### M40

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Claude M40-1・Codex M40-1 | High | 在庫の公開 API が relation を返すと、受け取る側が `unscope`・`rewhere`・`update_all` を呼べ、scope と書き込みの入口が境界を越える。`adr/002`「AR モデルは公開しない」と「公開 API は値を返す」に反する | 作るもの 1 の表と、判断「別のコンテキストの値を、SQL の中でどう渡すか」を足した。在庫の公開 API `Inventory::Allocation.active_quantities_sql(actor)` が、scope を掛けた後に SQL の文字列にした副問い合わせを、列の名前と一緒に値（`SqlSubquery`）で返す。relation を返す案と、ID の配列で受け取る案を比べた案に書いた。`graphql-schema.md`「1 回のリクエストがたどる道」3 に書くことを「文書に残すこと」に足した |
| Claude M40-2 | Medium | 引当数量の副問い合わせから scope を外しても、他社の引当は自社の受注明細に結ばれないので、行列の 2 回目の比較では捕まらない | 作るもの 4 と完了条件。行列で捕まらない理由を書き、`allocation_spec.rb` に、RLS を開いてから副問い合わせを流し、他社の引当が入らないことを対照つきで確かめる example を足した |
| Claude 読み直し 1 の違和感 4 | Medium | `SqlSubquery` を文字列で結ぶと、CI の Brakeman が SQL の埋め込みを警告しうる | 判断「別のコンテキストの値を、SQL の中でどう渡すか」。`Arel.sql` で包み、警告が出たら `config/brakeman.ignore` に指紋と理由を書くとした |

### M33

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Claude M33-1・Codex M33-1 | High | かんばんの 7 列を `first: 10` で予算の表の `more_lists` に書くと、親が 20 件の回に 10 件しか返らず、いまの予算の spec（返す件数が親の件数と等しい）が落ちる。7 つの状況の親を 1 回で作る準備も要る | 作るもの 3 の「かんばんの列」。かんばんを別の画面の問い合わせ `SupplierKanban` にし、予算の表の一覧の行に 1 ページの上限（`page_size: 10`）を持たせて、返す件数を親の件数と上限の小さい方と比べる形に広げるとした。予算の世界は 7 つの状況の受注を 1 回で 1 件ずつ足す |
| Claude M33-2・Codex M33-2 | Medium | 最初に落とすテストが書かれていない | 完了条件。`frontend/e2e/list-pagination.spec.ts` の 1 ページ目と 2 ページ目の example と、予算の spec の画面の問い合わせのファイルの一覧の example を名指しし、画面の部品が無いことによる読み込みの失敗を RED に数えないとした |
| Claude M33-3 | Low | E2E の世界の品目は 21 件ではなく 22 件（取り込みで ITM-021 が増える） | 作るもの 4 の「一覧のページ」。22 件にし、件数を `demo_world_spec.rb` で確かめると書いた |

### M41

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Codex M41-1・Claude M41-6 | High | `daily-reset` の Role が Pod を読めない。Deployment の `status.replicas` は終了中の Pod を数えないので、0 にしただけでは接続が残りうる | 作るもの 2 の Role を、Deployment の `get`、`deployments/scale` の `get`・`patch`、Pod の `list` の 4 つにした。作るもの 3 の手順 2 で、ラベルで引いた Pod の一覧が空になるまで待ち（上限 5 分）、`deploy_manifests_spec.rb` で Role の規則を、`demo_reset_spec.rb` で待ちを確かめる |
| Codex M41-2・Claude M41-5 | High | async のモードでは全ワーカーが 1 つの接続プールを分け合うのに、`jobs` のプールの大きさが決まっていない | 作るもの 2 の環境変数の表。`jobs` の `RAILS_MAX_THREADS` を 20 にし、Solid Queue の README の接続の数の段落を引いて決め方を書いた。`deploy_manifests_spec.rb` が `config/queue.yml` から必要な数を計算して確かめる。PostgreSQL の `max_connections` を 40 にした |
| Claude M41-1 | High | 本番の環境のセッションの Cookie は `Secure` で、actionpack は `request.ssl?` が偽の応答に `Secure` の Cookie を書かない。Next から http で呼ぶ Rails はログインの `Set-Cookie` を返さない | 作るもの 6 を足した。本番の環境で `config.assume_ssl = true` にし、`production_boot_spec.rb` で http の `POST /session` が `Secure` の Cookie を返すことを確かめる。`adr/009` 決定 2 にも書いた |
| Claude M41-2 | High | 本番の環境で止めているシードの公開 API は `Inventory::Stocks.set_safety_stock` を含めて 3 つある。2 つだけを許すと、作り直しが安全在庫の段で止まる | 作るもの 4。`git grep ProductionEnvironment` で集めた 3 つを正本にし、`demo_world_spec.rb` が `DemoWorld.build` を最後まで流して確かめるとした。完了条件に `onboarding_spec.rb`・`stocks_spec.rb` を足した |
| Claude M41-3 | High | 毎日 DB ごと消すことは、監査ログの保存期間（7 年）と「表を落とす DDL はレビューで止める」に反するのに、「保証は変えない」とだけ書く | 作るもの 3 の末尾と `adr/009` 決定 3・引き受けるコスト。トリガーは変えないが、公開の配置の監査ログは 1 日で消え、保存期間と DDL の規則の対象外であることと、そう言える条件を書いた。`data-model.md`「監査ログ（`platform`）」に書くことを「文書に残すこと」に足した |
| Claude M41-4 | High | 共有のアカウントでは、1 人のログアウトがセッションの世代を進め、同じアカウントのほかの訪問者を全員切る | OI-149（`blocked-user`）を起こし、既定（公開の配置の `web` にだけ `SHARED_DEMO_ACCOUNTS=1` を渡し、ログアウトで世代を進めない）を作るもの 7 に書いた。`sessions_spec.rb` で両方の振る舞いを確かめる |
| Codex M41-3 | Medium | 本番の `config/database.yml` は接続先を持たず、`DB_HOST` を読むのは開発とテストだけ | 作るもの 2 の環境変数の表。本番の 2 つの設定が `DB_HOST`・`DB_PORT` を読むように直すとした |
| Codex M41-4・Claude M41-10 | Medium | PostgreSQL 18 のイメージはデータを `/var/lib/postgresql/18/docker` に置くので、流用元の 16 の置き場を写すと PVC の外に書く。タグも小版まで固定していない | 作るもの 2 の `postgres` の行。PVC を `/var/lib/postgresql` に付け、18 の小版まで固定したタグにした。`deploy_manifests_spec.rb` で置き場を確かめる |
| Codex M41-5 | Medium | `DemoWorld` と `Partnerships::Onboarding` が本番の環境で動かないことを前提にした設計文書の文（`graphql-schema.md` の操作者のいない入口と監査ログ、`data-model.md`「RLS」）を直す作業が無い | 「文書に残すこと」に 3 か所を挙げた |
| Codex M41-6 | Medium | `demo:reset` の入口の拒否を確かめる spec が完了条件に無い | 完了条件の `demo_reset_spec.rb`。変数が無いか `1` でなければ Kubernetes の API も DB のタスクも呼ばずに止まること、`1` なら作り直しの間だけ `DISABLE_DATABASE_ENVIRONMENT_CHECK` を立てることを確かめる |
| Claude M41-7 | Medium | `ensure` が走らない止まり方（OOM・Raspberry Pi の停止）と、Job の再試行で DB を何度も消すことが書かれていない | 作るもの 3。Job に `backoffLimit: 0` と `activeDeadlineSeconds: 1800` を書き、`deploy/README.md` に戻し方を書くとした |
| Claude M41-8 | Medium | `web` と `jobs` に渡す環境変数と Secret が決まっていない（`SECRET_KEY_BASE`・`FRONTEND_ORIGIN` など） | 作るもの 2 に、コンテナごとの環境変数の表と理由を置き、`deploy_manifests_spec.rb` が表とマニフェストの一致を確かめるとした |
| Claude M41-9 | Medium | `adr/009` の見直す条件が、この配置で集めないメトリクスの警報を条件にしている | `adr/009`「見直す条件」と作るもの 9 の手順 4。作者が実機で、取り込みを流しながら発注から受注の確定までの時間を画面で測る形にした |
| Claude M41-10 | Low | `db:drop` の本番の保護を外す方法の原文と、自分の接続を返すことが書かれていない | 作るもの 3 の手順 3。`check_protected_environments!` の原文の場所を引き、消す前に自分の接続をプールに返すとした |
| Claude M41-11 | Low | (b) `adr/009` の「ファイルの受け口は外から届かない」が、Next を通して届く形と食い違う。(c) `emptyDir` の上限を超えると Pod が追い出される | `adr/009` 決定 2・得られるもの と 作るもの 5。(b) 外から届く Rails の入口は Next を通した取り込みのファイルの受け口だけ、と直した。(c) 上限を超えると追い出されること、作り直しが毎日 Pod を作り直すので溜まるのは 1 日分であることを書いた。(a) の大きさは「直さなかった指摘」 |
| Claude 読み直し 1 の違和感 1・Codex 読み直し 1 の違和感 1 | Medium | 作るもの 2 の環境変数の表に `SHARED_DEMO_ACCOUNTS` が無く、マニフェストから抜けても spec が落ちない | 表に `web` だけの行を足した |
| Claude 読み直し 1 の違和感 2 | Medium | `assume_ssl` を有効にすると、本番の環境のミドルウェアの並びを許した一覧と比べる `logging_spec.rb` が落ちる | 作るもの 6 で `ActionDispatch::AssumeSSL` を一覧に足すとし、完了条件のコマンドに `logging_spec.rb` を足した |
| Claude 読み直し 1 の違和感 3 | Medium | 本番の環境の DB はテストと CI に無いので、子のプロセスで `POST /session` を流す方法が要る | 完了条件の `production_boot_spec.rb`。子のプロセスの中で `Partnerships::Authentication.authenticate` を差し替え、`Rack::MockRequest` で流すとした |
| Claude 読み直し 1 の違和感 5 | Low | ログアウトで世代を進めないと、写し取られた Cookie が使えるままになることが書かれていない | 作るもの 7 と OI-149 に書いた |
| Codex 読み直し 1 の違和感 2 | Low | OI-147 と `adr/009` が、資源の見積もりを「作るもの 6」と指す（いまは作るもの 8） | 2 か所を作るもの 8 に直した |

## 指摘の根拠を確かめた結果

指摘の根拠は、リポジトリのコードと、インストール済みの gem で確かめた。

| 根拠 | 結果 |
|---|---|
| 予算の spec は、どの一覧も返す件数が親の件数と等しいことを求める（M33-1） | 正しい。`spec/graphql/query_budget_spec.rb` の `expect_lists` |
| 本番の環境で `ProductionEnvironment` を上げるのは 3 か所（Claude M41-2） | 正しい。`git grep ProductionEnvironment` の `lib/demo_world.rb`・`packs/partnerships/app/public/partnerships/onboarding.rb`・`packs/inventory/app/public/inventory/stocks.rb` |
| `DISABLE_DATABASE_ENVIRONMENT_CHECK` で本番の保護を飛ばす（Claude M41-10） | 正しい。activerecord 8.1.4 の `lib/active_record/tasks/database_tasks.rb` の `check_protected_environments!` の 1 行目 |
| async のモードは、プロセスの中のワーカーの要るものを足し合わせる（M41-2） | 正しい。solid_queue 1.7.0 の README の「Fork vs. async mode」と接続の数の段落 |
| 本番の `database.yml` は接続先を持たない（Codex M41-3） | 正しい。`config/database.yml` の `production` に `host` が無い |
| 18 のイメージの置き場（Codex M41-4） | 正しい。本リポジトリの `compose.yaml` のコメント |
| ログアウトはセッションの世代を進める（Claude M41-4） | 正しい。`app/controllers/sessions_controller.rb` が `Partnerships::Authentication.revoke_sessions` を呼ぶ |
| `Secure` の Cookie を http の応答に書かない（Claude M41-1） | Claude が actionpack 8.1.4 の `lib/action_dispatch/middleware/cookies.rb` の `write_cookie?` を、Codex が読み直しで同じ箇所と `assume_ssl.rb` を引いた。手元では `config/application.rb` の `secure: Rails.env.production?` だけを確かめた |

## 作者の判断を待つ行

計画は、どの行も既定で書いた。各マイルストーンは既定で進めてよいが、`--due` の検査で、引当先のマイルストーンを終えられない。

| ID | 問い | 既定 | 止まる箇所 |
|---|---|---|---|
| OI-144 | 並べ替えの列を一覧の表に限るか（表に無い値での並べ替えと在庫の検索をやめる） | 限る | M33 を終えられない |
| OI-145 | 公開の画面のホスト名 | `factory-ops-rails.hayatec.dev` | M41 を終えられない |
| OI-146 | 毎日の作り直しの時刻と、Raspberry Pi を夜に止めているか | 日本時間の 4:30、起動から 6 時間の内なら流す | 同上 |
| OI-147 | Raspberry Pi の機種とメモリ | 8GB とみなす | 同上 |
| OI-148 | 公開の配置で訪問者に許す操作 | すべて許し、毎日の作り直しで戻す | 同上 |
| OI-149 | 共有のアカウントのログアウト | 公開の配置ではセッションの世代を進めない | 同上 |

## 直さなかった指摘と、台帳に積んだもの

- マイルストーンの大きさ（Claude M39-3・M41-11 (a)、Codex の違和感）：M39・M33・M41 は、本書の冒頭の「1 回の作業で終わる大きさ（数百行）」を超えそうである。分けると 1 つのサイクルの上限（6 つ）を超え、番号と台帳の参照も動くので、この計画では分けなかった。途中で完了を判定できる形に分けるかを、改善の候補 IB-67 に積んだ。
- 違和感は改善の候補に移した。
  - Codex 初回・Claude M39-3：1 回の作業に収まらないマイルストーンを、途中で完了を判定できる形に分けるか（IB-67）
  - Claude 初回：件数が正しいことを公開 API ごとではなく 1 か所で確かめるか（IB-68）
  - Claude 初回：状況ごとの件数を `GROUP BY` にしたとき、0 件の状況を返す形を検査で守るか（IB-69）
  - Claude 初回：流用元で一度も動いていない毎日のリセットの形を、実機の手順で先に確かめるか（IB-70。M41 の作者の手順 3 に、効き方を 1 回見ることを書いた）
  - Claude 初回：作者への問いを足すときは、台帳の行を先に直してから作者に渡す。この計画では、OI-144 と OI-149 を台帳に書いてから、`handoff.md` と PR の本文に載せた。サイクル 04 の再発防止（作者の判断は台帳から読む）のとおりなので、改善の候補には積まない
