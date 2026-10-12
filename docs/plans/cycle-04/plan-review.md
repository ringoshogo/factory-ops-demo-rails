# サイクル 04 の計画レビュー：M37・M30〜M33 への反映

この文書は、`implementation-plan.md` の M37・M30・M31・M32・M33 を 2 系統の独立したレビュー（Claude と Codex）にかけ、指摘を計画に反映した記録である。M37 から M33 に着手する担当者と、計画をレビューする人が読む。担当者は、計画の節が「なぜこう書いてあるか」をここで引ける。

M33（フロントエンド）は作者の方針で最後に実装するが、`guides/dev-cycle.md`「全体の流れ」のサイクルの表でサイクル 04 に入っているので、このレビューに含めた。M33 はサイクル 01 で計画レビューを済ませているので、サイクル 03 までの変更（役割の制限・M37・M30〜M32・業務の今日の時刻帯）との食い違いを中心に読ませた。

レビューに出す前に、取りまとめ役が計画を観点ごとに読み直し、コードと照らして直した（`122dd68`）。初回のレビューは、その版を読んだ。依頼には読む版の commit を書いた。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた控えのファイルから結果を読んだ。2 系統の High を直した版を、この文書と一緒に Codex で読み直した（読み直し 1、`16a79bd`）。そこで出た High を直した版を、Codex でもう一度読み直した（読み直し 2、`5cd4ffa`）。読み直し 2 は Conditional Go で、名指しされた完了条件の書き方を直した。

読む順は、マイルストーンごとの判定 → 指摘ごとの対応 → 指摘の根拠を確かめた結果 → 取りまとめ役が読み直しで直したこと → 作者の判断 → 直さなかった指摘と台帳に積んだもの、である。指摘の出典は次の形で示す。

| | Claude | Codex |
|---|---|---|
| 初回 | `<マイルストーン>-<番号>`（`M30-1` など） | `P<番号>` |
| 読み直し 1・2 | — | `N<番号>` |

Codex は、初回の指摘にも `M30-1` の形の ID を振った。Claude の ID とぶつかるので、この文書では Codex の初回の指摘を `P01`〜`P13` に振り直した。対応は、M37-1→P01、M37-2→P02、M30-1→P03、M30-2→P04、M30-3→P05、M30-4→P06、M31-1→P07、M31-2→P08、M31-3→P09、M32-1→P10、M32-2→P11、M33-1→P12、M33-2→P13 である。

## 判定

| マイルストーン | 初回 Claude | 初回 Codex | 読み直し 1 Codex | 読み直し 2 Codex |
|---|---|---|---|---|
| M37 RLS が隠す scope の抜けと、読み取りの役割を行列で捕まえる | Conditional Go | Conditional Go | Go | Go |
| M30 メトリクス | Conditional Go | Conditional Go | Go | Go |
| M31 SLO と障害対応の手順書 | Go | Conditional Go | Go | Go |
| M32 シードデータ | Conditional Go | Conditional Go | Conditional Go | Conditional Go |
| M33 フロントエンド | Conditional Go | Conditional Go | Go | Go |

全体の判定は、初回は 2 系統とも Conditional Go だった。Claude は High を 3 件、Codex は High を 8 件挙げ、それを直せば Go とした。Conditional Go は再レビューを要しないが、2 系統を合わせて High が 9 件あり、M32 には公開 API を足す直しが入ったので、直した版を Codex で読み直した。読み直しは High が出たときだけ続け、2 回までにした。

2 系統が同じことを挙げた指摘は次の 4 つである。

- 行列のダッシュボードの問い合わせが 2 つの集計を読まず、世界にも当たる行が無いので、scope を外しても落ちない（Claude M37-1、Codex P01）
- `DemoWorld` の冪等と固定の中身が、M33 の E2E の世界（同じ DB にワーカーごとに作る）と両立しない（Claude M32-5、Codex P12）
- ヒストグラムのバケットが無く、M31 の 60 秒・300 秒・900 秒の割合を取れない（Claude M30-6、Codex P04）
- exporter が要る `webrick` が依存に無い（Claude M30-2、Codex P05）

片方だけが挙げた High は次のとおりである。

- Claude だけ：発注の登録の文書を画面の問い合わせの一覧に足すと、既存のクエリ数の予算と複雑度の spec が落ちる（M30-1）
- Codex だけ：例外で 500 になった操作がメトリクスから抜ける（P03）、取り込みの停滞を測る系列が無い（P07）、ファイルの後始末と取り込みの開始の競合（P08）、テナントとユーザーと安全在庫を作る公開 API が無い（P10）

読み直しでは、前の High の指摘が解消したかと、High 以上の新しい指摘だけで判定した。

- **読み直し 1**：前の High 9 件をすべて解消と判定した。M32 に新しい High の N01（シードがジョブを実行した後に、実行待ちの行と同時実行の制御のセマフォが残る）が出た。
- **読み直し 2**：N01 を解消と判定した。N01 の直しで足した完了条件に、新しい High の N02（セマフォの行は返した後も残るので、「残らない」を確かめる spec は正しい実装でも落ちる）が出た。Codex は、N02 の完了条件を直せば Go とし、再判定は要らないとした。N02 を直し、M37・M30・M31・M33 は Go、M32 は N02 を直して Go で、M37 から着手できる。

## 指摘と対応

重大度は、2 系統で違うときは高い方を採った。「直した節」は、断りが無ければ `implementation-plan.md` の節である。各表は、初回の指摘、読み直しの指摘の順に並べる。

### M37

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| M37-1・P01 | High | ダッシュボードの 4 つの公開 API のうち `below_safety_stock`・`due_within` は、行列の問い合わせが読まず、世界にも当たる行が無いので、scope を外しても 2 回目の行列が落ちない | 作るもの 2 の (3)(4)。行列の `SupplierView.dashboard` で全フィールドを読み、`MatrixWorld` の全ペルソナに各集計に当たる行（安全在庫を割る在庫・期限の近い出荷依頼・未請求の明細）を持たせ、ガードで、設定を `on` にして scope を外すと各集計が変わることを確かめる |
| P02 | Medium | `viewer.partnerCode` の `member` を `:value` と書いて落とすのは、仕様に基づく RED にならない | 完了条件。最初に落ちるのを `matrix_world_spec.rb` のガード（補助が無いと 0 行）にし、`member` の期待は仕様の値で初めから書く |
| M37-2 | Low | ポリシーの補助をどの行列のファイルに掛けるか、フックの順が無い | 作るもの 2 の (1)。`MatrixWorld.share_per_file(cross_read: true)` にして順を固定し、`graphql_matrix_spec.rb` と `matrix_world_spec.rb` に掛け、`table_matrix_spec.rb` には掛けない |

### M30

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| M30-1 | High | `PlacePurchaseOrder` を画面の問い合わせの一覧に足すと、`query_budget_spec.rb` と `query_complexity_spec.rb` が落ちる | 作るもの 3。登録の表を `queries` と `mutations` に分け、mutation の文書は一覧に置かない。M31 の SLI はラベル `operation_type` で query を選ぶ |
| P03 | High | `graphql.operation_completed` は正常に戻ったときだけ出るので、例外で 500 になった操作が成功の割合から抜ける | 作るもの 2 の表。`ensure` で `result` を `error` にして 1 回だけ出してから上げ直す。`graphql_entry_spec.rb` に例外の example を足した |
| P04・M30-6 | High | ヒストグラムのバケットが無い。既定は最大 10 秒で、SLO の閾値の割合を取れない | 作るもの 2 の表に「バケット（秒）」の列を足し、SLO の閾値（0.5・1・60・300・900）を境界に含めた。spec で閾値の前後が別の `le` に数えられることを確かめる |
| P05・M30-2 | High | `webrick` が依存に無い。ポートとアドレスは環境変数でしか渡せず、`PORT` は Puma も使う。Web の exporter を立てる場所が無い | 作るもの 1 と 4。`webrick` を足し、`PROMETHEUS_EXPORTER_PORT` を必須にし、Web は Puma の起動のフック、ワーカーは `SolidQueue.on_start` で立て、test の環境では立てない |
| P06・M30-3 | Medium | `DirectFileStore` のディレクトリを決める時点・空にする時点・ゲージの集計・収集のブロックを動かすプロセスが決まらない | 作るもの 4。ディレクトリは初期化子で `METRICS_PROCESS` から選び、空にするのは exporter を持つプロセスの fork の前、収集のブロックは `jobs` だけに登録し、ゲージは `aggregation: :most_recent` |
| M30-4 | Low | フレームワークのイベントの単位と、`result` の値の写し方が無い | 作るもの 2。ミリ秒を秒に、`enqueued_at` の文字列を時刻に、`success` を `ok` に写すと書いた |
| M30-5 | Low | `FORBIDDEN` の出どころが、`unauthorized_field` と宣言漏れを扱っていない | 作るもの 2 の表。`unauthorized_field` を `object` に含め、宣言漏れを `undeclared` にし、M31 の警報に載せた（OI-124） |

### M31

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| P07・M31-1 | High | `import_rows_total` は累積値で、実行中の取り込みの停滞と、取り込みが無い時間を分けられない | M30 の作るもの 2 に `queue_claimed_jobs` を足し、警報を「`imports` のキューに実行中のジョブがあるのに 15 分行が増えない」にした。`alerts_test.yml` に 3 つの系列を足した |
| P08 | High | 後始末と `startImport` の競合が決まっていない | 作るもの「取り込まれないファイルの後始末」。どちらもファイルの行をロックし、後始末はロックの後に別の文で確かめ直し、開始は中身が消えていれば `CONFLICT`。`purge_lock_spec.rb` で両方の順を流し、`lock_sites_spec.rb` の表に足す（OI-122） |
| P09 | Medium | 28 日の SLO に、30 日の倍率（14.4・6）を書いている | 作るもの「警報の規則」。13.44 倍・5.6 倍にし、倍率の出し方を書いた。`alerts_test.yml` に倍率の境目の前後を足した |
| M31-2 | Low | 画面の問い合わせの速さの式が、query と mutation を分けられることに依存する | M30-1 の直しの `operation_type` で書いた |
| M31-3 | Low | `imports` を止めて `events` を先に流す止血と、同時実行の上限を下げる止血が、いまの構成では効かない | 手順書の表。キューはワーカーを分けていること、止めても実行中のジョブは止まらないこと、上限の変更はデプロイであることを書いた |
| M31-4 | Low | メンテナンスの切り替えで止まる入口の範囲が分からない | 作るもの「メンテナンスの切り替え」と手順書。GraphQL とファイルの受け口を止め、ログインと Webhook は止めない（OI-126）。spec で確かめる |

### M32

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| M32-5・P12 | High | `DemoWorld` の冪等と固定の中身が、M33 の E2E の世界と両立しない（一意のコードとメールアドレスがぶつかる） | 作るもの 1。`DemoWorld.build(namespace:, variant:)` の契約（名前空間・中身の変種・返り値・名前空間ごとの冪等）を書き、`demo_world_spec.rb` で 2 組の同居を確かめる。M33 の E2E の世界もこの形に直した |
| P10 | High | テナントとユーザーを作る公開 API と、安全在庫を設定する公開 API が無い | 作るもの 5。`Partnerships::Onboarding.register` と `Inventory::Stocks.set_safety_stock` を足し、単体の spec を完了条件に入れた（OI-125） |
| P11 | Medium | 失効した発注側の `buyer.suppliers` の期待が「値を返す」になっている | 完了条件。失効した側は取引先・カタログ・出荷が空になり、自社の発注と受領請求書は残ると書いた |
| M32-2 | Medium | 作者の判断を待つ行の直しを確かめる spec が、完了条件のコマンドに無い | 作者の判断を待つ行の箇条と完了条件。案ごとの spec のパスを書き、コマンドに足した |
| M32-3 | Medium | 受注日・検収日・発行日は公開 API が今日で決めるので、今日からの差では作れない | 作るもの 3。シードを流した日にし、入力で渡す日付だけを差で書く（OI-123） |
| M32-4 | Medium | 流し方がイベントのジョブだけで、取り込みが進まない | 作るもの 4。イベントと取り込みのジョブをその場で流し、通知は `bin/jobs` に任せる |
| M32-6 | Medium | 作者の判断を待つ行が M33 の着手を止めること、OI-06 を M32 の終わりの条件に置く理由が書かれていない | OI-06 の引当先を M33 にし、M33 の著者判断 8 で確かめると書いた。M32 は残りの 3 つ（OI-117・OI-118・OI-120）を待つが、M33 は着手の前に作者に著者判断を確かめるので、そのときまでにそろうと書いた |
| M32-1 | Low | テナントの境界とコンテキストの境界への影響が書かれていない | 作るもの 6 を足した |
| N01 | High | シードがジョブを `ActiveJob::Base.execute` と `finished!` で流すと、実行待ちの行と、`Imports::RunJob` の `limits_concurrency` のセマフォが残る。同じテナントの次の取り込みが 1 時間待たされ、`bin/jobs` が同じジョブをもう一度動かす | 作るもの 4。実行の後に、ワーカーと同じ順で `ready_execution` を消して `finished!` にし、`unblock_next_blocked_job` でセマフォを返す（solid_queue 1.7.0 の `claimed_execution.rb`）。`demo_world_spec.rb` で、実行待ちの行が残らず、次の取り込みが blocked にならないことを確かめる |
| N02 | High | N01 の直しで書いた「取り込みのセマフォが残らない」は、solid_queue のセマフォの行が返した後も値を戻して残るので、正しい実装でも落ちる | 作るもの 4 の完了条件（`demo_world_spec.rb`）。セマフォが上限の値（1）に戻り、次の取り込みが ready になることを確かめる形にし、行が残ることの原文（`semaphore.rb` の `signal`）を引いた |

### M33

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| M33-2 | Medium | 画面の問い合わせの正本を `frontend/graphql/` に移すと、mutation の文書と詳細の問い合わせで既存の予算と複雑度の検査が落ちる。撤退コスト「小」が合わない | 判断「画面の問い合わせの正本」。予算と複雑度は query だけを対象にし、予算の表に一覧の行を足し、撤退コストを中にした。完了条件に 2 つの spec と `metrics_subscriber_spec.rb` を足した |
| （読み直し 1 の参考） | Medium | 予算の spec は query の文書と表の行の一致を確かめるので、詳細の問い合わせの扱いも要る | 判断「画面の問い合わせの正本」。query の文書のすべて（一覧と詳細）の行を予算の表に足すと書いた |
| P13・M33-3 | Medium | 画面 18・20 が、一覧の中にコネクションを入れ子にする形のまま（OI-17） | 作るもの 2 の画面の表。取引先の一覧と、選んだ 1 社の `buyer.supplier(supplierTenantId:)` のカタログに分けた |
| M33-1 | Low | `admin` に限る操作の印が一部の画面にしか無い。取り込みの開始は種類で役割が変わる | 作るもの 2。`admin` に限る操作を画面ごとに挙げ、取り込みは種類 `items` の選択肢だけを `admin` に出すと書いた |
| M33-4 | Low | 業務の日付を Next が決めると、業務の今日を決める場所が 2 か所になる | 作るもの 3。Next では決めず、API の `businessDate` を使う |

## 指摘の根拠を確かめた結果

指摘の根拠は、リポジトリのコードと、インストール済みの gem で確かめた。yabeda・yabeda-prometheus・prometheus-client は手元に無いので、2 系統が取得した原文の引用に頼った。

| 根拠 | 結果 |
|---|---|
| 行列の `SupplierView.dashboard` は `salesOrderCounts` と `unbilledTotal` だけを読む（M37-1・P01） | 正しい。`spec/matrix/graphql_expectations.rb` の `SupplierView.dashboard` の `query` |
| 画面の問い合わせの一覧は query だけを許す（M30-1） | 正しい。`spec/graphql/query_budget_spec.rb` の一覧の example が `all(eq("query"))` を確かめる |
| `webrick` が依存に無い（P05・M30-2） | 正しい。`Gemfile.lock` に `webrick` が無い |
| `yabeda-prometheus` 0.9.1 は `prometheus-client` を 5 未満に限る | 正しい。`gem specification -r yabeda-prometheus -v 0.9.1` の依存 |
| 発注日は公開 API が `Date.current` で決める（M32-3） | 正しい。`packs/purchasing/app/public/purchasing/ordering.rb` の `order_date: Date.current` |
| `bin/jobs` の supervisor は fork の前に `on_start` を呼ぶ（M30 の作るもの 4） | 正しい。solid_queue 1.7.0 の README「Lifecycle hooks」 |
| セマフォを返しても行は消えず、値を足すだけである（N02） | 正しい。solid_queue 1.7.0 の `app/models/solid_queue/semaphore.rb` の `signal` が `attempt_increment` で `value + 1` に更新する |
| `finished!` は終わりの時刻を書くだけで、セマフォを返さない（N01） | 正しい。solid_queue 1.7.0 の `app/models/solid_queue/job/executable.rb` の `finished!` と、`claimed_execution.rb` の `finalize` が後で呼ぶ `unblock_next_blocked_job`（`job/concurrency_controls.rb`、公開のメソッド） |
| 既定のバケットが最大 10 秒（P04・M30-6）、`DirectFileStore` のゲージの既定の集計が `:all` で `pid` を足す（P06） | 2 系統が yabeda-prometheus 0.9.1 の `adapter.rb` と prometheus-client 4.2.5 の `direct_file_store.rb` を引いた。手元では確かめていない |

## 取りまとめ役が読み直しで直したこと

レビューに出す前に、取りまとめ役が計画を観点ごとに読み直し、コードと照らして次を直した（`122dd68`）。

- M37：完了条件の「ダッシュボードの 4 つの公開 API のどれか」を、壊す 6 つの公開 API の名前で書き、RLS と scope を片方ずつ壊す記録を足した
- M30：いまのコードが出していないイベント（`notifications.provider_responded`・`notification.accepted`）と、トップレベルのエラーの種別を、足す作業として表に書いた。`bin/jobs` が fork するので、exporter を 1 つの「ワーカーのプロセス」で立てる書き方を直した。OI-119・OI-121 の spec のパスを書いた
- M31：`FORBIDDEN` の増加を警報にすると、サイクル 03 で増えた `admin` に限る操作を `member` が呼ぶだけで鳴るので、返すオブジェクトの規則の拒否に限った（OI-124）。`promtool` を `bin/check-alerts` で流し、`ci_checks_spec.rb` の照らしに入れた。メンテナンスの切り替えと、OI-116 の後始末（OI-122）の spec を名指しした
- M32：シードは GraphQL を通らない入口なので、`admin` に限る操作の公開 API を呼ぶ前に同じ規則を評価すると書いた（`dev-cycle.md`「1. 計画レビュー」の観点 1）。完了条件を spec にした
- M33：業務の今日を OI-117 に合わせ、`handoff.md` を指していた古い参照を `guides/dev-cycle.md` に直した
- 台帳：OI-118・OI-120 の引当先を M30 から M32 にした。どちらも作者の判断を待つ行で、M30 に置くと `--due M30` が M30 を終えさせず、前提の表で M31〜M33 の着手まで止める。M32 はシードで GraphQL を通らない入口から公開 API を呼び、単価の訂正の理由も書くので、2 つの答えを使う

## 作者の判断

レビューの後に、作者が 3 つの行を決めた（2026-10-12）。台帳で `decided` にし、結果の欄に判断と理由と反映先を書いた。計画は、どの案でも成り立つ書き方から、決まった形に書き直した。

- **OI-117（業務の今日）**：(a)。`config.time_zone` を `Asia/Tokyo` にし、業務の今日をすべて日本時間で決める。ダッシュボードの `Asia/Tokyo` の直書きを外し、既存の行は書き換えない。業務の規則を `context-map.md`「検収と請求の流れ」に、ダッシュボードの今日を `graphql-schema.md`「読み取りの一覧」に書いた。実装は M32 の作るもの 9 に、シードより先に作るものとして入れた。M32 はシードと画面の日付がこれで決まり、もともと OI-117 の引当先だったので、新しいマイルストーンは作らない。時刻帯を混ぜる呼び出しを Cop（`Rails/Date`・`Rails/TimeZone`）で止め、日本時間の 0〜9 時の境目の example を足す
- **OI-118（操作者のいない入口の公開 API）**：(a)。規則を `graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」に書いた。テナントが決まる前のログインとテナントの作成だけを、`Tenancy.require_tenant!` の例外にした。規則に合わない既存の箇所を直す作業を M30 の作るもの 7 に入れ、引当先を M32 から M30 に戻した。RLS が他社の行を隠すので所有の条件を外しても単体は落ちず、M37 の補助で RLS の SELECT を開いて確かめる。M31 の後始末の公開 API は、この規則で作る
- **OI-120（`correctItemPrice` の理由の上限）**：200 文字。`graphql-schema.md`「mutation の一覧」の上限の表に行を足し、実装を M30 の作るもの 8 に入れ、引当先を M30 に戻した

この反映はレビューの後の変更で、2 系統のレビュアーには読ませていない。読み直しは 2 回までと決めているので、反映した節は、M30・M32 の実装レビューの観点 1（計画への準拠と範囲）で読む。

作者の判断を待つ行は、次の 2 つが残る。

| ID | 問い | 止まる箇所 |
|---|---|---|
| OI-06 | GitHub のリポジトリを public にする時期 | M33 を終えられない |
| OI-07〜OI-14 | M33 の著者判断 1〜8 | M33 に着手できない（着手の前に確かめる） |

## 直さなかった指摘と、台帳に積んだもの

- 取りまとめ役が決めた振る舞いは、`judgment` で台帳に積んだ。作者の確認を待つが、実装は計画のとおりに進める。
  - OI-122：取り込まれないファイルの中身を 24 時間で消す定期のジョブと、消えたファイルへの開始を `CONFLICT` にすること
  - OI-123：シードの中身（流用元の品目 20 件、発注側の 2 社の名前、日付）
  - OI-124：`FORBIDDEN` の出どころのラベルと、警報に載せる出どころ
  - OI-125：シードのために足す 2 つの公開 API
  - OI-126：メンテナンスの切り替えで止める入口
- 違和感は改善の候補に移した。
  - Claude：M37 で行列の要求が 2〜3 倍になるのに、遅くなったときにすることが無い（IB-50）
  - Claude：`notification.accepted` と `notification.delivery_failed` が、コミットの前に出る（IB-51）
  - Claude：OI-119・OI-121 はメトリクスと関係の無い確かめで、M30 の目的の文に現れない。サイクル 03 の棚卸しの置き方のままにし、台帳に積まなかった
  - Codex：M30 で購読者を足すと、購読者を 1 つに固定した `logging_spec.rb` が落ちる。M30 の作るもの 2 と完了条件に書いた
  - Codex：`plans/cycle-03/inventory.md`・`conformance.md` には OI-118・OI-120 の引当先が M30 と残る。証跡は書き換えず、いまの引当先は台帳と `handoff.md` に書いた
