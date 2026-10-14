# テストの層と重要シナリオ

テストを書く人が、テストのファイルをどこに置き、何をどの層で確かめるかを決めるときに読む。テストの大半は、速く、落ちた場所から原因が分かる単体テストに置く。壊れると事故になる業務の流れだけを、シナリオテストで端から端まで確かめる。

## テストの層

テストを書く人は、ファイルを足すとき、どの層の置き場に置くかを次の表で決める。置き場の正本は `config/test_layers.yml` で、表を変えるときは両方を同じ変更で直す。

| 層 | 置き場 | 確かめること | 割合の警告 |
|---|---|---|---|
| 単体 | `packs/*/spec`（`packs/*/spec/concurrency` を除く） | 1 つのパッケージの公開 API・モデル・policy・状況の導出。DB は使うが、GraphQL とイベントの配送は通さない | — |
| 結合 | `spec/requests`・`spec/contracts` | GraphQL の入口から公開 API までの配線、イベントの配送表と受け手のつながり | — |
| シナリオ | `spec/scenarios`・`spec/concurrency`・`packs/*/spec/concurrency` | 下の重要シナリオと競合テスト、シードと E2E の世界（`DemoWorld`）を公開 API とイベントで作り切れること、一覧のために写した値が元と一致すること（`spec/scenarios/read_model_copies_spec.rb`） | 50% を超えたら |
| ガード | `spec/matrix`・`spec/graphql`・`spec/db`・`spec/packwerk`・`spec/jobs`・`spec/notifications`・`spec/platform`・`spec/rubocop`・`spec/bin` | 構造の規則（列挙テスト・行列テスト・到達可能性・テナントの強制・外部への作用の呼び出し元）と、`bin/` の検査のスクリプト | 数えない |

割合は、単体・結合・シナリオの 3 つの層の example の数で数える。ガードは、表・型・入口の数に比例して増えるので、割合に数えない。

画面（`frontend/`）のテストは rspec の外にあり、`bin/test-layers` は数えない。画面のテストを足す人は、URL の値を問い合わせの変数に写す関数と、Rails の呼び出し口・Cookie・エラーの分け方は単体（`frontend/lib/**/*.test.ts`、Vitest。画面の検査のスクリプトの単体は `frontend/scripts/**/*.test.mjs`）に、画面を通す流れ・全画面の寸法とコントラスト・集計の数と飛び先の一覧の件数の一致は E2E（`frontend/e2e/`、Playwright）に置く。E2E が測る画面の一覧は `app/` のルートから集めるので、画面を足すと測る対象にも入る。

CI は、rspec の JSON の出力を `bin/test-layers` に渡し、層ごとの件数・割合・時間を表にしてジョブの要約に書く。

```sh
bundle exec rspec --format progress --format json --out tmp/rspec.json
bin/test-layers tmp/rspec.json
```

`bin/test-layers` は、example の層を JSON の `id`（`./packs/sales/spec/public/sales/catalog_spec.rb[1:2:1]` の形）のファイルの部分で決める。`file_path` は、共有の example（`it_behaves_like`）では共有の example を定義したファイルを指すので使わない。どの層の置き場にも当たらないファイルがあれば失敗する。割合は報告するだけで、テストを割合に合わせて書き足したり移したりしない。割合は機能の種類で揺れ、未分類さえ止めれば数え方は崩れないからである。警告の注釈（`::warning::`）は、見直すべき大きな偏り（シナリオが 50% を超える）にだけ出し、失敗にはしない。単体を厚くすることは、割合ではなく、業務の分岐を足した PR がその分岐の単体の spec を足しているかを実装レビューで見て守る（`dev-cycle.md`「実装レビュー」の観点 4）。

## 層への配分

テストを書く人は、業務規則の分岐（数量の上限、状況ごとの拒否、導出表の各行）を単体で網羅する。上限（件数・文字列の長さ・ファイルの大きさ・値の型の上限）は、上限ちょうどで受け付ける example と、上限 + 1 で拒む example の両方を、定数から作らず仕様の値で書く。上限 + 1 だけでは上限を誤って 1 つ下げても落ちず、定数から入力を作ると定数を誤って変えても通るからである。計画が名指ししていない、実装の中で増えた上限にも当てる。一覧を返す公開 API の単体のテストでは、親を 2 件以上作る。1 件だと N+1 の検出が働かない（[graphql-schema.md「ページングと N+1」](../architecture/graphql-schema.md#ページングと-n1)）。結合の request spec は、入口ごとに、成功 1 本と、公開 API の失敗が `UserError` に写ること 1 本を基本にする。request spec の補助（ログインする `login_as`、応答の本文をそのまま返す `graphql_body`、トップレベルのエラーが無いことを確かめて `data` を返す `query`）は `spec/support/request_helpers.rb` にあり、`type: :request` の spec と重要シナリオに取り込まれる。テストを書く人は、補助を spec のファイルに複製しない。

業務の日付を今日で決める公開 API（発注日・検収日のように、入力で受けずに `Date.current` で決めるもの）を足す人は、日本時間の 0〜9 時に `travel_to` して、日付が日本時間の日付になる example を単体に置く。この時間帯だけ UTC の日付と食い違うので、ほかの時刻では時刻帯の誤りが落ちない（時刻帯の決め方は `guides/config.md`「application.rb で変えたこと」）。

`audit` を宣言した mutation を足す人は、結合の spec で、成功の後にできた監査の行の対象（`target_type`・`target_id`）と相手（`counterparty_tenant_id`）を、期待する値と比べる。行の件数だけを見る example は、宣言のラムダが対象か相手を取り違えても落ちない。`spec/graphql/audit_examples_spec.rb` が、スキーマの `audit` の action ごとに、action の文字列と 2 つの列の名前が同じ spec のファイル（`spec/requests`・`spec/scenarios`・`spec/concurrency`）に現れることを確かめる。名前が現れることしか見ないので、比べ方が正しいかは実装レビューの観点 4 で見る。

既存の request spec から単体へ移してよいのは、公開 API の spec と同じ業務の分岐を確かめているものだけである。次の規則は HTTP の入口でしか確かめられないので、request spec に残す。

- 認証：セッションの無い要求と、世代の古いセッションの要求が 401 になる
- セッション：Cookie の属性、ログインでのセッションの作り直し、ログアウトでの世代の更新
- 認可の配線：視点・型・mutation の宣言が、入口を通した要求で効く
- トランザクションの単位：ユーザーエラーだけの応答はコミットし、トップレベルのエラーと例外はロールバックする（[graphql-schema.md「1 回のリクエストがたどる道」](../architecture/graphql-schema.md#1-回のリクエストがたどる道)）

request spec の example を単体へ移す人は、消す example の `expect` を 1 つずつ、移し先の example に対応づける。対応先の無い `expect` が確かめていた性質（応答が同じであること、イベントが 1 件であること、など）は、移し先に `expect` を足すか、request spec に残す。移した分岐は実装がすでにあるので、書いた時点で通り、RED では抜けが見えない。対応づけた表は証跡に残す。

## 分岐の網羅率の警告

PR を出した実装者は、実装レビューに出す前に、CI の test のジョブの要約と差分の行の警告の注釈を読み、足した行か変えた行にある分岐のうち、どの example も通らないものに対処する。分岐を一度も通らない example の抜けを、レビューだけに頼らずに見つけるためである。

CI は、rspec を `COVERAGE=1` で流して分岐ごとの通過の回数を `tmp/coverage.json` に書き、`bin/check-branch-coverage` がそれを基準の ref との分岐点からの差分と照らす。基準は、PR では向き先のブランチ、main への push では push の前の先端である（[bin.md「CI が使うもの」](bin.md#ci-が使うもの)）。手元で同じ一覧を見るときは、全件を流してから照らす。一部の spec だけを流すと、流さなかった spec が通す分岐まで未通過に出る。

```sh
COVERAGE=1 bundle exec rspec
BASE_REF=origin/<向き先のブランチ> bin/check-branch-coverage
```

一覧には 2 つの種類が出る。実装者は、どちらも example を足すか、足さない理由を PR の本文に分岐かファイルごとに書く。

| 一覧 | 意味 | 実装者がすること |
|---|---|---|
| どの example も通らない分岐 | 足した行か変えた行が、分岐の条件の行か腕の中にあり、その腕の通過の回数が 0 である | その分岐を通り、結果を確かめる example を足す。届かない防御の分岐のように足さないなら、理由を書く |
| 計測なし | 差分にある計測の対象のファイルを、どの example も読み込まなかった | そのファイルを使う example を足す |

照合では、腕ごとに、条件の始まる行と腕の範囲の行を、足した行と変えた行に当てる。条件だけを変えた変更も、既存の腕の中に行を足した変更も拾う。`else` の無い `if` の書いていない側は、条件の行だけに当てる。Ruby がこの側を `if` の全体の座標で返すので、範囲で当てると、書いた側の中の変更でも出るからである。注釈は腕の始まる行に付く。名前を変えたファイルと、まだ commit していないファイルは、全行を足した行として数える。行を消しただけの変更は、作業ツリーに当てる行が無いので拾わない。`when` の条件だけを変えた変更も拾わない。Ruby は `when` の腕を本体の行から始め、`when` の行の座標を返さないからである。

`bin/check-branch-coverage` は警告を出すだけで、終了コードは 0 である。網羅率は、example が分岐を実行したかだけを見て、結果を確かめたかを見ないからである。警告が出ないことは、次の 3 つの抜けが無いことを意味しない。これらは実装レビューの観点 4（`dev-cycle.md`「実装レビュー」）で見る。

- **通った分岐の別の入力**：Ruby の分岐の網羅率は `&&`・`||` を分岐に数えない。条件の片側だけを満たす入力の example が無くても、`if` の両方の腕を通れば警告は出ない
- **確かめの抜け**：分岐を通る example が、その分岐の結果を `expect` で確かめていなくても、通ったことになる
- **子のプロセスで動くコード**：計測するのは rspec のプロセスが読み込んだ `app/`・`packs/*/app/`・`packs/*/lib/`・`lib/` の Ruby のファイルだけである（`config/branch_coverage.yml`）。`bin/` のスクリプト、`config/`・`db/`、本番の起動を見る spec の子のプロセスは測らない

警告の件数と、そのうち example を足した件数は、取りまとめ役が実装レビューの証跡に書き、サイクル末の振り返りが合計して評価する（`dev-cycle.md`「実装レビュー」、`cycle-end.md`「1. 振り返り」）。

## 競合テスト

2 つの接続から同時に操作するテスト（競合テスト）は、`concurrency` の置き場に置く。公開 API だけを使うものは `spec/concurrency` に、パッケージの非公開のモデルを使うものは `packs/<パッケージ>/spec/concurrency` に置く。パッケージの外からは、非公開の定数を参照できないからである。競合でない example は、同じ対象の example でも単体の置き場に置く。

`spec/rails_helper.rb` は、`concurrency` の置き場のファイルに `:concurrency` のメタデータを、置き場から付ける（`define_derived_metadata`）。`bin/test-layers` の層の判定も、この置き場から決まる。このメタデータの example は、Bullet の N+1 の検出（[graphql-schema.md「ページングと N+1」](../architecture/graphql-schema.md#ページングと-n1)）の外にある。Bullet は検出の状態をスレッドごとに持ち、別のスレッドの読み込みが見えないからである。

パッケージのコードで行ロックかアドバイザリロックを取るメソッドを足した人と、本体でロックを取る DB の関数（トリガーなど。`FOR SHARE` を含む）を足した人は、そのロックで直列になることを確かめる競合テストを書くか、競合テストを持たない理由を書く。どちらも `spec/db/lock_sites_spec.rb` の表に、メソッド（「定数.メソッド」）か関数（「DB:関数名」）ごとに書く。spec は構文木からロックを取るメソッドを、`db/structure.sql` からロックを取る関数を集め、表と食い違えば落ちる。トリガーは公開 API を通らない書き込みにも効くので、ロックを取る位置（条件で行を絞る前か後か）の誤りは、競合テストでしか見えない。競合テストを書いた行は、その spec が `concurrency` の置き場にあり、メソッドを呼ぶ文字列を含むことを確かめる。ロックを足しても、直列になることを確かめなければ、ロックを外しても何も落ちない。表は、どのロックを競合テストが守り、どのロックが理由だけで残るかを、実装レビューが差分で読める形にする。ロックを取らずに一意索引で同時の配送を止める受け手（`INSERT ... ON CONFLICT DO NOTHING` で冪等にするもの）は、この表の外にあるので、書いた人が同時の配送の競合テストを書く。逐次の 2 回の配送は、事前に存在を確かめる形に替えても通るからである。

競合テストを書く人は、`spec/support/concurrency.rb` の補助を使い、次のように書く。

1. `self.use_transactional_tests = false` にする。example ごとのトランザクションの中では、接続が 1 本に固定され、2 つの接続にならない。
2. 先の操作を `hold_open` で、コミットせずに開いたままにする。
3. 後の操作を `in_thread` で別の接続から始め、`blocked_on_lock?(後のスレッド, by: 先のスレッド)` で、後の接続が先の接続のロックを待っていることを確かめる。補助は 2 つの接続の pid を控え、`pg_blocking_pids` で待ちの相手を確かめるので、無関係な接続の待ちを数えない。待たずに終わる操作は、ロックで直列になっていない。操作の途中で止めるためにスレッドの間で値を受け渡して待つ（`Queue#pop` など）ときは、`ConcurrencyHelpers::WAIT_SECONDS` の期限を付ける。期限が無いと、止める包みを外したときや先の操作が途中で失敗したときに待ち続け、手順 5 の後始末に届かない。
4. 先の操作を `commit` でコミットさせ、後の操作の結果を `finish` で受け取る。どちらもスレッドの例外を送出し直すので、先の操作のコミットの失敗も隠れない。
5. 作った業務の行を、example の後で `delete_owned_rows` に消させる。補助は、開いたままのトランザクションをすべて閉じさせ、スレッドが終わったことを確かめてから、所有ロールの接続でそのテナントの業務の行と、そのテナントの ID を引数に含むジョブ（イベントのジョブと送信のジョブ）を消す。アプリのロールの接続では、RLS が他のテナントの行を隠すので消せない。確定した請求書と、それに結んだ集計と明細、販売単価の行（`item_prices`）は、所有ロールの削除もトリガーが拒む（[data-model.md「請求（`billing`）」](../architecture/data-model.md#請求billing)、[ADR 006](../adr/006-販売単価を有効期間と記録期間の2軸で持つ.md) 決定 3）ので、補助は後始末のトランザクションの中だけその表のトリガーを止めて消し、コミットの前に戻す。スレッドが終わらなければ、行を消さずに失敗する。消した後に、`owner_tenant_id` を持つ表（残す表を除く）にそのテナントの行が残っていれば、渡す表の書き漏らしとして失敗する。`delete_owned_rows` を最後まで終えずに終わった `:concurrency` の example は、`spec/support/concurrency.rb` の設定の `after` が落とす。この補助は、`:concurrency` のメタデータと同じく `spec/rails_helper.rb` が読み込むので、spec のファイルで読み込まなくても効く。呼び忘れた example がコミットしたイベントのジョブは、テナントで絞らない `deliver_enqueued_events` に後の example で拾われ、離れた example の失敗になるからである。このガードは、渡すテナントの漏れ（factory が暗に作ったテナント）は捕まえない。`spec/concurrency/cleanup_guard_spec.rb` が、後始末を呼ばない example と、`after` があっても後始末を終えない example が落ちることを確かめる。

競合テストは、GraphQL の入口を通すと監査の行を作る（[graphql-schema.md「監査ログ」](../architecture/graphql-schema.md#監査ログ)）。監査の行は所有ロールでも消せず（[data-model.md「監査ログ（`platform`）」](../architecture/data-model.md#監査ログplatform)）、所有テナントは外部キーで消せない。そのため、後始末はテナント・ユーザー・監査の行を消さずに残す。相手テナントとユーザーは外部キーの無い参照なので消せるが、監査の行が消えた行を指さないように、これも残す。`delete_owned_rows` は、`tenants`・`users`・`audit_logs` を渡されると失敗する。

残った行は、同じテスト DB に次の実行を流したときに、一意の制約で新しい行とぶつかる。テストを書く人は、残る行の一意の値（テナントの `code`・`partner_code`、ユーザーの `email`）を、すべて乱数で作る。factory の `sequence` は、プロセスごとに 1 から数え直すので使わない。factory の `tenant` と `user` は乱数で作るので、そのまま使ってよい。

`spec/concurrency/post_shipment_audit_spec.rb` は、同じ出荷依頼の `postShipment` を、2 つの接続から GraphQL の入口を通して送り、成立した 1 件だけが監査の行を持つことを確かめる。公開 API を直接呼ぶ競合テストは監査の行を作らないので、これが無いと、残った監査の行がある DB に競合テストを流し直す経路を確かめられない。競合テストは、同じテスト DB で `bundle exec rspec --tag concurrency` を 2 回続けて流しても通ることを確かめる。

## 重要シナリオ

シナリオは、2 社のユーザーとしてログインし、GraphQL の入口を通して操作する。イベントは、Active Job のアダプタを `:solid_queue` のまま、`deliver_enqueued_events` で受け手まで流す（[ADR 005](../adr/005-イベントのジョブをトランザクション内で登録する.md) 決定 6）。補助は `spec/support/scenarios.rb` にある。`deliver_enqueued_events` は、シードと同じ `DemoWorld::Jobs`（`lib/demo_world/jobs.rb`）で流すので、テストとシードでジョブの流し方と後始末が食い違わない。

イベントの受け手を足す人と、受注・発注・出荷依頼・取り込みの状況の値を足す人は、`DemoWorld` の世界も合わせる。`spec/contracts/receivers_spec.rb` は、シードの世界を作る間にすべての受け手へイベントが届くことを対照にして、受け手の戻り値を確かめる。`spec/scenarios/demo_world_spec.rb` は、E2E の世界が状況の止まっていられる全値の行を持つことを確かめる。世界を合わせないと、受け手や状況を足した変更でこの 2 つが落ちる。品目のコードか名前を書く公開 API を足す人は、同じトランザクションで在庫の写しを書き（`Inventory::ItemLabels.put`）、その経路を `DemoWorld` が通るようにするか、`spec/scenarios/read_model_copies_spec.rb` にその経路で品目を変えた後に作り直しが何も書かないことを確かめる example を足す。一致の spec は、`DemoWorld` と、そこに書いた経路しか捕まえないからである（`../adr/011-在庫の一覧のために品目のコードと名前を同期で写す.md` 決定 2）。

`spec/rails_helper.rb` は、`spec/scenarios` のファイルに `:scenario` のメタデータを、置き場から付ける。テストを書く人が手でタグを付けないので、付け忘れで `bundle exec rspec --tag scenario` から漏れることがない。同じ置き場の `demo_world_spec.rb`・`seeds_spec.rb`（シードと E2E の世界）も `--tag scenario` で流れる。`spec/spec_helper.rb` は `config.fail_if_no_examples = true` にし、絞り込みの結果が 0 件の実行を失敗にする。rspec-core 3.13 には、この設定に当たるコマンドラインの引数が無い。

| | シナリオ | 確かめること | 置き場 |
|---|---|---|---|
| S1 | テナントの境界 | 発注側が、イベントで受け取った相手の ID（出荷実績 ID）と、受注側の伝票の ID を、ID を取るすべての入口（下の列挙）に持ち込んでも、相手のデータに届かない | `spec/scenarios/tenant_boundary_spec.rb`。画面でテナントを切り替えた後に前のテナントの行が出ないことは `frontend/e2e/tenant-switch.spec.ts` |
| S2 | 取引関係の失効 | 失効で 3 経路と新しい発注が閉じ、連結済みの取引は請求まで進む | `spec/scenarios/revocation_spec.rb`。画面で通すのは `frontend/e2e/revocation.spec.ts` |
| S3 | 発注と受注の連結 | 照合待ち → 対応表の登録 → 受注確定。同じイベントを 2 回流しても、イベントの届く順を入れ替えても、受注は 1 件で、発注の状況は同じになる | `spec/scenarios/order_linking_spec.rb` |
| S4 | 引当・出荷・取消の競合 | 同じ出荷依頼の同時の計上は 1 件だけ成立する。同時の引当と出庫で有効在庫が負にならない。同時の取消と計上はどちらか一方だけが成立する | `spec/concurrency/`・`packs/*/spec/concurrency/` |
| S5 | 請求の金額と税の丸め | 発注 → 受注 → 出荷 → 検収 → 締め → 発行 → 受領請求書で、単価・数量・税額・合計が 2 社で一致し、税が請求書・税率ごとに 1 回だけ切り捨てられる | `spec/scenarios/billing_amounts_spec.rb` |

### S1 の入口の列挙

`tenant_boundary_spec.rb` は、`FactoryOpsSchema` の型を走査し、ID 型の引数（入力型の中の ID 型の項目を含む）を取るフィールドと mutation を集める。spec は、入口ごとに、相手の ID をどの引数に入れるか、どの種類の ID を入れるか、届かないときの結果を表で持つ。集めた入口が表に無いか、表の入口がスキーマに無ければ落ちる。ID を取る入口を足した人は、S1 の表に行を足す。

届かないときの結果は、入口の種類で決まる。

- 1 件を引くフィールドは `null` になる
- 一覧を ID で絞るフィールドは空になる。spec は、同じ入口を絞らずに引いた一覧が空でないことを先に確かめる。絞らない一覧も空なら、絞った一覧が空でも絞り込みを確かめたことにならないので、準備に自社の行を足す
- 表に自社の ID（`own`）を書いた入口は、その ID を入れて自社の行が返ることを、相手の ID を入れる前に確かめる。絞り込みの入力型の ID（`SalesOrderFilter.customerTenantId` など）と 1 件を引くフィールド（`supplier.item(id:)`）がそうで、自社の ID でも何も返らない入口は、相手の ID で空か `null` になっても境界を確かめたことにならない
- 対象を引く mutation は `NOT_FOUND` になる
- `placePurchaseOrder` は、相手の有無と取引関係を区別しない `NOT_PERMITTED` になる（[graphql-schema.md「ID と `node`」](../architecture/graphql-schema.md#id-と-node)）

### 行列テストとの分担

行列テストは、全表・全入口を 5 つのペルソナで 1 段ずつ確かめる。シナリオは、段をつないだ道（イベントで知った ID を別の入口に持ち込む、など）を確かめる。テストを書く人は、行列テストに行を足して済むものをシナリオにしない。

行列テストの 2 ファイル（`spec/matrix/table_matrix_spec.rb`・`spec/matrix/graphql_matrix_spec.rb`）は、世界（`spec/support/matrix_world.rb`）をファイルごとに 1 回だけ作り、全 example で使い回す（`MatrixWorld.share_per_file`）。example ごとに作ると、表の数に比例する大きさの世界を、表の数に比例する件数だけ作るので、時間が表の数の 2 乗で伸びる。世界は `before(:context)` で接続を固定した外側のトランザクションの中に作り、`after(:context)` で巻き戻す。各 example は、rspec-rails が同じ接続に開くセーブポイントの中で動き、終わりに巻き戻る。

行列の spec を書く人は、次の 2 つを守る。

- 別の接続を使わない（`OwnerConnection`・スレッド・`use_transactional_tests = false`）。別の接続からは、コミットしていない世界の行が見えない。別の接続でコミットした行は、example の終わりに巻き戻らない。例外は、下の RLS の SELECT と UPDATE を開くポリシーの足し外しだけで、補助が世界を開く前と閉じた後に所有ロールの接続で行う。
- 世界のオブジェクトを書き換えない。オブジェクトは example の間で使い回し、DB の巻き戻しでは戻らない。`MatrixWorld` は世界が持つインスタンスの属性を凍らせ、属性の代入を `FrozenError` にする。`reload`・`destroy` と、関連先のインスタンスの書き換えは捕まえないので、呼ばない。

補助は、世界のトランザクションがファイルの終わりより前にコミットされたか巻き戻ったら、`after(:context)` で失敗させる（`unpin_connection!` が偽を返す）。世界を作った後にテナントの設定が残っていても失敗させる。残った設定は外側のトランザクションの終わりまで全 example に渡り、生 SQL の RLS の結果を変えるからである。`spec/matrix/matrix_world_spec.rb` が、example で足した行とテナントの設定が次の example に残らないことと、ファイルの終わりに世界が残らないことを確かめる。

入口の行列は、読み取りの行ごとに、同じ要求を RLS の SELECT を開いて送り直し、本文が変わらないことも確かめる。認可の scope は RLS に任せない（`../architecture/graphql-schema.md`「認可」）が、相手から読む経路の無い表では、公開 API が scope を外しても RLS が他社の行を隠すので、1 回目の応答は変わらないからである。結果の種類だけを比べると、集計を返す入口（`supplier.dashboard`）は scope を外しても種類が変わらないので、本文を比べる。並びだけが変わったときは、scope の抜けと区別して「並びの決まらない一覧」として落とす。仕組みは次のとおりである。

- `MatrixWorld.share_per_file(self, cross_read: true)` は、世界を開く前に、テナントの表ごとに、設定 `app.matrix_cross_read` が `on` のときだけ全行を読ませる SELECT のポリシー（`matrix_cross_read`）と、全行を UPDATE の対象に入れる UPDATE のポリシー（`matrix_cross_update`）を所有ロールの接続で足し、世界を閉じた後に外す（`spec/support/matrix_cross_read.rb`）。UPDATE のポリシーは下の操作者のいない入口の単体のためのもので、入口の行列は読み取りしか送らないので効かない。ポリシーの足し外しは表のロックを取るので、世界のトランザクションが開いている間に行うと待ち合う。足すのは 1 つのトランザクションなので、途中で失敗しても残らない。外すのは足し終えたときだけで、この判定は `MatrixCrossRead.share`（グループの前後）と `with_policies`（ブロックの間）だけが持つ。ポリシーを使う補助と spec はこの 2 つを通し、`remove!` を直に呼ばない。呼ぶ側が足し外しを対にして書くと、足すのに失敗しても外す形を補助ごとに書き直すことになるので、`spec/matrix/cross_read_spec.rb` が直の呼び出しを落とす。接続先の名前がテストの DB でなければ足さずに失敗する
- 設定は example の中で `MatrixCrossRead.on!` が `SET LOCAL` と同じ形で入れ、example のセーブポイントと一緒に戻る。ロールや DB の既定には書かない
- ポリシーの SQL は `spec/support` にだけ置き、`lib/tenant_table.rb` とマイグレーションには置かない。アプリのロールは `app.*` の設定を自由に変えられるので、本番に載れば全テナントの行を読む抜け道になるからである。`structure.sql` に混ざれば `bin/check-structure` が、消し忘れれば `spec/db/tenant_enforcement_spec.rb`（テナントの表のポリシーは `owner_write` と 6 つの表の `partner_read` だけ）が落とす
- `spec/matrix/matrix_world_spec.rb` が、2 回目が空振りしないことを確かめる。設定を `on` にした生 SQL がどの表でも全ペルソナの行を読み、ダッシュボードの 4 つの公開 API から scope を外すと、公開 API の値も入口の要求の応答も他社の行で変わることである。世界は、どのペルソナにもダッシュボードの各集計に当たる行と、一覧の絞り込みに当たる行を持つ
- 件数も 2 回目の比較にかけるため、コネクションを返すフィールドの行は、問い合わせで `totalCount` を読む。並べ替えと絞り込みを持つ一覧は、両方を渡す変種の行（`"SupplierView.salesOrders#filter"` の形）を持つ。並べ替えを持つ一覧は、2 つの列で並べる `thenBy` を渡す変種の行（`"SupplierView.salesOrders#thenBy"` の形）も持ち、`spec/matrix/graphql_matrix_spec.rb` が、`thenBy` を受け取るフィールドをスキーマから集めて行があることを確かめる。2 つ目からの列は結ぶ表も条件も足さないので、この行が捕まえる scope の抜けは無く、列の向きと値の無い行の置き場の正しさは `packs/platform/spec/models/page_spec.rb` だけが確かめる。`spec/matrix/graphql_matrix_spec.rb` が、コネクションを返すフィールドをスキーマから集めて行の問い合わせが `totalCount` を選ぶことと、変種の行の絞り込みがどのペルソナでも 0 件より多く、絞らない一覧の件数より少ない件数に絞ることを確かめる。当たる行が無いか全行が当たると、絞り込みの scope の抜けが 2 回目の比較に出ないからである。状況でも絞る変種の行（受注・発注・出荷依頼）は、状況を外した件数より少なく絞ることも確かめる。列の絞り込みだけで世界が絞れるので、列には当たり状況で外れる行が世界に無くても、前の確かめは通るからである。絞り込みの項目を足す人は、`MatrixWorld#add_filter_rows` に当たる行と外れる行を足す。行ごとに 1 行を引くスカラーの副問い合わせで並べる列（取引先の名前、品目の今日の単価と安全在庫、出荷依頼の出荷予定日）を足す人は、その列で並べる変種の行（`"SupplierView.salesOrders#orderByName"` の形）を足す。結ぶ条件を誤って 2 行以上が当たると、どのペルソナの応答も SQL のエラーになって落ちる
- 1 つのテストの DB で、行列の spec と「RLS の SELECT と UPDATE を開く」の文脈を使う spec を、同時に 2 つの実行から流さない。ポリシーの名前は実行ごとに変わらないので、後から足す実行は「ポリシーがすでにある」で失敗する。並行で流すときは、別名のテストの DB を使う。途中で止めた実行が残したポリシーも同じ失敗になるので、ほかに流している実行が無いことを確かめてから `bin/rails runner -e test 'require "./spec/support/matrix_world"; MatrixCrossRead.remove!'` で外す
- 表の行列（`table_matrix_spec.rb`）には掛けない。表の行列は生 SQL で RLS そのものを確かめるからである

入れ子のフィールドが親の値から取った ID で呼ぶ公開 API（dataloader の一括取得と、親の ID を渡す resolver）は、入口の行列の応答では scope の抜けが見えない。親と同じテナントの子しか引かないので、scope を外しても RLS の SELECT を開いても、応答が変わらないからである。入口の行列は、これらの公開 API に全ペルソナの ID を直に渡し、RLS の SELECT を開いても呼んだペルソナの ID にだけ値を返すことを確かめる（`spec/matrix/graphql_expectations.rb` の `NESTED_APIS`）。`app/graphql` が親の ID で呼ぶ公開 API を足したのに行が無ければ、列挙の完全性の example が落ちる。

入口の行列が確かめるのは、GraphQL の入口から届く読み取りだけである。GraphQL を通らない操作者のいない入口の公開 API（通知の宛先・認証の操作者・取り込みの再登録・単価の移行・品目の写しの書き込みと作り直し・出荷依頼の受注番号の写しの作り直し・イベントの受け手。[graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」](../architecture/graphql-schema.md#認可宣言の無い型リゾルバmutation-は拒否する)）の所有の条件は、その公開 API の単体が確かめる。単体は、共有の文脈「RLS の SELECT と UPDATE を開く」（`spec/support/cross_read.rb`）で同じ 2 つのポリシーをグループの前に足して後に外し、example の中で `cross_read!` を呼んでから他社の対象を渡して、他社の行を数えず、変えないことを確かめる。同じ example で、開いた後に他社の行が見えることと、自社の対象なら公開 API が読み書きすることを先に確かめる（対照）。

状況の SQL の式が子の行を読む副問い合わせ（受注の式が結ぶ在庫の引当数量、出荷依頼の式が読む出荷停止）と、一覧が結ぶ写しの表と副問い合わせ（在庫の一覧が品目のコードと名前で並べ、検索するために結ぶ品目の写しと、品目の一覧が安全在庫で並べるために結ぶ在庫の副問い合わせ）も、入口の行列では所有の条件の抜けが見えない。他社の子の行は他社の親を指し、自社の親には結ばれないので、RLS の SELECT を開いても状況が変わらないからである。品目の写しと在庫の副問い合わせも、品目 ID が UUIDv7 で他社の品目と重ならないので、結ぶ条件から所有テナントを外しても自社の在庫と品目に他社の行は結ばれない。他社の名義で自社の親を指す行は公開 API とイベントでは作れないので、式と一覧の側の単体が同じ文脈でその行を factory で作り、`cross_read!` の後も引当数量・状況・並びと検索に入らないことを確かめる（`packs/inventory/spec/public/inventory/allocation_spec.rb`・`packs/fulfillment/spec/models/fulfillment/shipment_request_status_spec.rb`・`packs/inventory/spec/public/inventory/item_labels_spec.rb`・`packs/sales/spec/public/sales/catalog_spec.rb`）。所有テナントと親の組の外部キーがある子の表（受注明細・入荷・検収・出荷指示・出荷実績）は、DB が他社の名義の行を拒むので、単体では確かめない（`../adr/010-状況の導出をSQLの式1つにする.md` 決定 3）。

UPDATE と `SELECT ... FOR UPDATE` で行を引く公開 API は、SELECT だけを開いても、RLS の UPDATE のポリシー（`owner_write`）が他社の行を対象から除くので、所有の条件を外しても単体が落ちない。そのため文脈は UPDATE のポリシーも開く。UPDATE のポリシーの `WITH CHECK` は `false` で、許可のポリシーの `WITH CHECK` は OR でつながるので、書いた後の行は `owner_write` の `WITH CHECK`（自社の行）だけで判定される。所有の条件を外した公開 API は、他社の行を引いて書こうとして RLS の違反の例外になり、example が落ちる。ただし、設定が `on` の間は、他社の行を自社の名義に書き換える UPDATE と `INSERT ... ON CONFLICT DO UPDATE` が `WITH CHECK` を通る。example は、`cross_read!` で開いたまま同じ接続で他社の行を読み直し、所有の列を含めて変わらないことを確かめて、この書き換えを捕まえる（文脈の `reread`）。所有ロールの接続で読み直さないのは、example のトランザクションの中で作った行と書き込みが別の接続から見えないからである。テストを書く人は、条件の付いた書き込み（出荷済の時刻が空のときだけ書く、など）には、書く側の分岐を通る他社の行を選ぶ。

`INSERT ... ON CONFLICT DO UPDATE` は、テナントをまたぐ一意索引で衝突すると他社の行を更新しにいく。公開 API は、更新の `WHERE` に所有の条件を書き、他社の行に当たったら失敗させる。文脈を開かなければ `owner_write` の `USING` が、開けば `WITH CHECK` が例外にするので、条件を外しても RLS の例外になり、条件があるときの失敗と区別できる（出荷停止の解除。`Fulfillment::SalesEventReceiver` の `release_hold`）。

次の 3 つの形は、文脈を開いても所有の条件の抜けが見えないので、所有の条件を書いたうえで単体では確かめない。どれも、所有の条件は別の守りと重なる二重の守りである。

- 冪等キーにグローバルな一意索引があり、キーが重なれば書かずに飛ばす受け手（`ON CONFLICT DO NOTHING` と、有無を読んでから作る形）：他社に同じキーの行を作れないので、他社の行を引く入力を作れない。出荷依頼の作成と出荷停止の記録（`Fulfillment::SalesEventReceiver` の `create_request`・`hold`）、受注の連結（`Sales::PurchaseOrderTranslator`）、請求対象の記録（`Billing::SalesEventReceiver`）、受領請求書の記録（`Purchasing::BillingEventReceiver`）がこれに当たる。一意索引が、他社の行への書き込みを止める
- 行ロックだけを取って書かない箇所：他社の行のロックは黙って通り、結果が変わらない。出荷停止の受け手が出荷依頼をロックする箇所（`Fulfillment::SalesEventReceiver` の `hold`）がこれに当たる。続けて書く出荷停止の行は、自社の名義で作る
- DELETE：文脈は DELETE のポリシーを開かないので、他社の行は DELETE の対象にならない。`owner_write` が他社の行を除く

接続の固定には `ActiveRecord::ConnectionPool#pin_connection!` を使う。Rails の公開の文書に無いメソッドで、rspec-rails の transactional fixtures が使うものと同じである。`lock_thread` は transactional fixtures の既定と同じ真にし、example の固定と形をそろえる（activerecord 8.1 の `active_record/test_fixtures.rb` の `class_attribute :lock_threads, default: true`。固定と入れ子の数え方は `active_record/connection_adapters/abstract/connection_pool.rb` の `pin_connection!`・`unpin_connection!`）。Rails の更新でこのメソッドの名前か入れ子の数え方が変わると、行列の spec は `before(:context)` か `after(:context)` で落ちる。そのときは、test-prof の `before_all` がその版で何を使っているかを確かめて移るか、`let(:world) { MatrixWorld.new }` で example ごとに作る形に戻す。test-prof の `before_all` も同じメソッドを包んでいるので、移るだけでは退路にならない。
