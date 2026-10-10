# テストの層と重要シナリオ

テストを書く人が、テストのファイルをどこに置き、何をどの層で確かめるかを決めるときに読む。テストの大半は、速く、落ちた場所から原因が分かる単体テストに置く。壊れると事故になる業務の流れだけを、シナリオテストで端から端まで確かめる。

## テストの層

テストを書く人は、ファイルを足すとき、どの層の置き場に置くかを次の表で決める。置き場の正本は `config/test_layers.yml` で、表を変えるときは両方を同じ変更で直す。

| 層 | 置き場 | 確かめること | 件数の目安 |
|---|---|---|---|
| 単体 | `packs/*/spec`（`packs/*/spec/concurrency` を除く） | 1 つのパッケージの公開 API・モデル・policy・状況の導出。DB は使うが、GraphQL とイベントの配送は通さない | 60% 以上 |
| 結合 | `spec/requests`・`spec/contracts` | GraphQL の入口から公開 API までの配線、イベントの配送表と受け手のつながり | 30% 以下 |
| シナリオ | `spec/scenarios`・`spec/concurrency`・`packs/*/spec/concurrency` | 下の重要シナリオと競合テスト | 10% 以下 |
| ガード | `spec/matrix`・`spec/graphql`・`spec/db`・`spec/packwerk`・`spec/jobs`・`spec/platform`・`spec/rubocop`・`spec/bin` | 構造の規則（列挙テスト・行列テスト・到達可能性・テナントの強制）と、`bin/` の検査のスクリプト | 数えない |

割合は、単体・結合・シナリオの 3 つの層の example の数で数える。ガードは、表・型・入口の数に比例して増えるので、割合に数えない。

CI は、rspec の JSON の出力を `bin/test-layers` に渡し、層ごとの件数・割合・時間を表にしてジョブの要約に書く。

```sh
bundle exec rspec --format progress --format json --out tmp/rspec.json
bin/test-layers tmp/rspec.json
```

`bin/test-layers` は、example の層を JSON の `id`（`./packs/sales/spec/public/sales/catalog_spec.rb[1:2:1]` の形）のファイルの部分で決める。`file_path` は、共有の example（`it_behaves_like`）では共有の example を定義したファイルを指すので使わない。どの層の置き場にも当たらないファイルがあれば失敗する。割合が目安を外れたときは GitHub の警告の注釈（`::warning::`）を出すが、失敗にはしない。割合は機能の種類で揺れ、未分類さえ止めれば数え方は崩れないからである。目安を 3 マイルストーン続けて外れたら、単体の割合の下限を失敗の条件に変える（`implementation-plan.md` M16「判断」）。続けて外れた数は、単体の spec の無い業務の分岐を単体に書き足した後（OI-22）から数える（OI-24）。

## 層への配分

テストを書く人は、業務規則の分岐（数量の上限、状況ごとの拒否、導出表の各行）を単体で網羅する。一覧を返す公開 API の単体のテストでは、親を 2 件以上作る。1 件だと N+1 の検出が働かない（[graphql-schema.md「ページングと N+1」](../architecture/graphql-schema.md#ページングと-n1)）。結合の request spec は、入口ごとに、成功 1 本と、公開 API の失敗が `UserError` に写ること 1 本を基本にする。

既存の request spec から単体へ移してよいのは、公開 API の spec と同じ業務の分岐を確かめているものだけである。次の規則は HTTP の入口でしか確かめられないので、request spec に残す。

- 認証：セッションの無い要求と、世代の古いセッションの要求が 401 になる
- セッション：Cookie の属性、ログインでのセッションの作り直し、ログアウトでの世代の更新
- 認可の配線：視点・型・mutation の宣言が、入口を通した要求で効く
- トランザクションの単位：ユーザーエラーだけの応答はコミットし、トップレベルのエラーと例外はロールバックする（[graphql-schema.md「1 回のリクエストがたどる道」](../architecture/graphql-schema.md#1-回のリクエストがたどる道)）

## 競合テスト

2 つの接続から同時に操作するテスト（競合テスト）は、`concurrency` の置き場に置く。公開 API だけを使うものは `spec/concurrency` に、パッケージの非公開のモデルを使うものは `packs/<パッケージ>/spec/concurrency` に置く。パッケージの外からは、非公開の定数を参照できないからである。競合でない example は、同じ対象の example でも単体の置き場に置く。

`spec/rails_helper.rb` は、`concurrency` の置き場のファイルに `:concurrency` のメタデータを、置き場から付ける（`define_derived_metadata`）。`bin/test-layers` の層の判定も、この置き場から決まる。このメタデータの example は、Bullet の N+1 の検出（[graphql-schema.md「ページングと N+1」](../architecture/graphql-schema.md#ページングと-n1)）の外にある。Bullet は検出の状態をスレッドごとに持ち、別のスレッドの読み込みが見えないからである。

競合テストを書く人は、`spec/support/concurrency.rb` の補助を使い、次のように書く。

1. `self.use_transactional_tests = false` にする。example ごとのトランザクションの中では、接続が 1 本に固定され、2 つの接続にならない。
2. 先の操作を `hold_open` で、コミットせずに開いたままにする。
3. 後の操作を `in_thread` で別の接続から始め、`blocked_on_lock?(後のスレッド, by: 先のスレッド)` で、後の接続が先の接続のロックを待っていることを確かめる。補助は 2 つの接続の pid を控え、`pg_blocking_pids` で待ちの相手を確かめるので、無関係な接続の待ちを数えない。待たずに終わる操作は、ロックで直列になっていない。
4. 先の操作を `commit` でコミットさせ、後の操作の結果を `finish` で受け取る。どちらもスレッドの例外を送出し直すので、先の操作のコミットの失敗も隠れない。
5. 作った行を、example の後で `delete_owned_rows` に消させる。補助は、開いたままのトランザクションをすべて閉じさせ、スレッドが終わったことを確かめてから、所有ロールの接続でそのテナントの行とイベントのジョブを消す。アプリのロールの接続では、RLS が他のテナントの行を隠すので消せない。スレッドが終わらなければ、行を消さずに失敗する。

## 重要シナリオ

シナリオは、2 社のユーザーとしてログインし、GraphQL の入口を通して操作する。イベントは、Active Job のアダプタを `:solid_queue` のまま、`deliver_enqueued_events` で受け手まで流す（[ADR 005](../adr/005-イベントのジョブをトランザクション内で登録する.md) 決定 6）。補助は `spec/support/scenarios.rb` にある。

`spec/rails_helper.rb` は、`spec/scenarios` のファイルに `:scenario` のメタデータを、置き場から付ける。テストを書く人が手でタグを付けないので、付け忘れで `bundle exec rspec --tag scenario` から漏れることがない。`spec/spec_helper.rb` は `config.fail_if_no_examples = true` にし、絞り込みの結果が 0 件の実行を失敗にする。rspec-core 3.13 には、この設定に当たるコマンドラインの引数が無い。

| | シナリオ | 確かめること | 置き場 | 作るマイルストーン |
|---|---|---|---|---|
| S1 | テナントの境界 | 発注側が、イベントで受け取った相手の ID（出荷実績 ID）と、受注側の伝票の ID を、ID を取るすべての入口（下の列挙）に持ち込んでも、相手のデータに届かない | `spec/scenarios/tenant_boundary_spec.rb` | M16 |
| S2 | 取引関係の失効 | 失効で 3 経路と新しい発注が閉じ、連結済みの取引は請求まで進む | `spec/scenarios/revocation_spec.rb` | M26 |
| S3 | 発注と受注の連結 | 照合待ち → 対応表の登録 → 受注確定。同じイベントを 2 回流しても、イベントの届く順を入れ替えても、受注は 1 件で、発注の状況は同じになる | `spec/scenarios/order_linking_spec.rb` | M16 |
| S4 | 引当・出荷・取消の競合 | 同じ出荷依頼の同時の計上は 1 件だけ成立する。同時の引当と出庫で有効在庫が負にならない。同時の取消と計上はどちらか一方だけが成立する | `spec/concurrency/`・`packs/*/spec/concurrency/` | M16（計上・引当・出荷指示の取消）、M22（受注の取消） |
| S5 | 請求の金額と税の丸め | 発注 → 受注 → 出荷 → 検収 → 締め → 発行 → 受領請求書で、単価・数量・税額・合計が 2 社で一致し、税が請求書・税率ごとに 1 回だけ切り捨てられる | `spec/scenarios/billing_amounts_spec.rb` | M25 |

### S1 の入口の列挙

`tenant_boundary_spec.rb` は、`FactoryOpsSchema` の型を走査し、ID 型の引数（入力型の中の ID 型の項目を含む）を取るフィールドと mutation を集める。spec は、入口ごとに、相手の ID をどの引数に入れるか、どの種類の ID を入れるか、届かないときの結果を表で持つ。集めた入口が表に無いか、表の入口がスキーマに無ければ落ちる。ID を取る入口を足した人は、S1 の表に行を足す。

届かないときの結果は、入口の種類で決まる。

- 1 件を引くフィールドは `null` になる
- 一覧を ID で絞るフィールドは空になる
- 対象を引く mutation は `NOT_FOUND` になる
- `placePurchaseOrder` は、相手の有無と取引関係を区別しない `NOT_PERMITTED` になる（[graphql-schema.md「ID と `node`」](../architecture/graphql-schema.md#id-と-node)）

### 行列テストとの分担

行列テストは、全表・全入口を 5 つのペルソナで 1 段ずつ確かめる。シナリオは、段をつないだ道（イベントで知った ID を別の入口に持ち込む、など）を確かめる。テストを書く人は、行列テストに行を足して済むものをシナリオにしない。
