# サイクル 3 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M36 行列テストの世界の作り方と、テストの検出力の小さな穴

PR #42（`m36-matrix-world`、base は `main`）。最初は `cycle-03-plan` を base に PR #41 で出したが、`cycle-03-plan` が main にマージされてブランチが消え、#41 が閉じたので、同じブランチで #42 を出し直した。どちらの系統も Go で、Critical と High は無かった。Medium と Low は同じブランチの commit で直し、直さなかった違和感は改善の候補に移した。High 以上が無いので、読み直しには出していない。どちらの系統も、`201290a..c1f7cc1` の diff を `c1f7cc1` の版で読んだ。Codex はテストを流さず、依頼に書いた実行結果を前提にした。Claude は `c1f7cc1` の worktree を別名のテスト DB で流し、世界の開閉を確かめるプローブの spec を 2 本書いて流した（消した）。

| 系統 | 判定 |
|---|---|
| Codex | Go |
| Claude | Go |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘なし |
| 正しさ | 指摘（X1・X2） | 指摘（C1） |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（X1・X2 の経路のテスト） | 指摘（C2） |
| 参照の維持 | 指摘（X3） | 指摘（C3・C4） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | X1：`pin_connection!` が `begin`・`ensure` の外にあり、固定と入れ子の数を足した後の接続の確かめか BEGIN で失敗すると、固定が残る | 固定を `begin` の中に入れ、失敗したら外す。接続を借りる前の失敗では固定が無いので、固定の無いことの例外だけを捨てる。確かめの失敗と借りる前の失敗の 2 つの example を足し、固定を `begin` の外に戻す変更と、例外を捨てない変更で、それぞれが落ちることを確かめた | `b680952` |
| Medium | Codex | X2：後始末のガードは `spec/support/concurrency.rb` を読み込んだ spec でしか登録されず、読み忘れた競合テストを単独で流すと効かない | `spec/rails_helper.rb` が `:concurrency` のメタデータと同じく必ず読み込み、各 spec の読み込みを消した。`rails_helper` の読み込みを外すと、競合テストが読み込みの時点で落ちる | `b680952` |
| Low | Codex | X3：`lock_threads` の既定値の原文の所在が無い | `guides/testing.md` に activerecord 8.1 の `test_fixtures.rb` と `connection_pool.rb` の所在を書いた | `b680952` |
| Medium | Claude | C1：凍らせても、`reload`・`destroy` と関連先のインスタンスの書き換えは `FrozenError` にならず、次の example に渡る。文書は書き換え全体を捕まえると読める | 機械で捕まえるのは属性の代入だけで、`reload`・`destroy`・関連先の書き換えは呼ばない規則で守ると、補助のコメント・`guides/testing.md`・OI-85 に書いた。いまの行列の spec はどれも呼ばない | `c9ee7f8` |
| Low | Claude | C2：`inventory_spec.rb`・`shipping_spec.rb` の `before` に、`login_as` と同じログインが手書きで残る | `login_as(member)` にした | `c9ee7f8` |
| Medium | Claude | C3：計画の判断の裏返る条件が、test-prof に移すとだけ書き、ガイドの移り先と食い違う | `b680952` で、ガイドと同じ移り先（`before_all` の依存を確かめて移るか、`let(:world)` に戻す）に直していた | `b680952` |
| Low | Claude | C4：IB-28 が `未着手` のまま | 移り先を書いたので `反映済み` にし、反映先を判定の記録に書いた | `c9ee7f8` |

違和感は次のように扱った。

- Codex 1：CI の中央値の完了条件はレビューの時点で確かめていない → 下の「確かめたこと」に 3 回の結果を書いた
- Codex 2：計画の裏返る条件に test-prof の旧記述が残る → C3 と同じ（`b680952`）
- Claude 1・2：世界のトランザクションを閉じた example を名指しできない。世界の接続で 2 回コミットすると世界が DB に残る → どちらも規則（OI-87）で守る範囲なので、IB-31 に積んだ
- Claude 3：ガードの外の spec の列挙に、何もコミットしない `matrix_world_spec.rb` が混ざる → コミットした行を消す 3 本と、何もコミットしない 1 本に分けて書いた（`c9ee7f8`）
- Claude 4：ガードを単独で流すと効かない → X2 の直しで解消した（`b680952`）

### 実装の記録

新しいガードの spec（`spec/matrix/matrix_world_spec.rb`・`spec/concurrency/cleanup_guard_spec.rb`）を、補助を変える前の `201290a` の上で流し、8 examples, 7 failures で落ちた。失敗は、`MatrixWorld.share_per_file`・`open` が無い `NoMethodError` と、ガードが無いので後始末をしない内側の example が通る期待の不一致だった。通ったのは「after で後始末を終えた example は通る」の対照だけである。`matrix_world_spec.rb` は最初の実装で 1 件落ち、世界を作った後の確かめで失敗したときに固定を外さない誤りを捕まえた（直してから commit した）。上限ちょうどの example は実装が先にあるので、書いた時点で通る。検出力は壊して確かめた。

壊したファイルは複製から戻し、壊すときと戻すときに更新時刻を進めた。

| 対象 | 壊して落ちること |
|---|---|
| 上限 | 検収の比較を `>=` にする・検収の上限を 1 下げる・調整の比較を `>=` にする・調整の上限を 1 下げる、で上限ちょうどの example が落ちる。上限を 1 上げると上限 + 1 の example が落ちる |
| 後始末のガード | 設定の `after` を外す（3 examples）・印を立てない（ガードの 4 examples と、実際の競合テストの全 example）・実際の競合テスト（`stock_lock_spec.rb`）から `after` を外す、で落ちる |
| 世界の補助 | 作る途中の失敗で固定を外さない・`close` が `unpin_connection!` の偽を無視する・凍らせない・テナントの設定を確かめない・接続の固定を `begin` の外で行う・固定の無いことの例外を捨てない、で落ちる |

落ちなかったのは、後始末の印を example ごとに下ろす `before` を外す変更だけである。rspec は example ごとにインスタンスを作り直すので、印は前の example から渡らない。`before` は置かず、計画の節を直した（OI-86）。

行列テストの検出力は、壊す箇所を 6 つ決め、変える前（`201290a`、別名のテスト DB）と変えた後（`827a4f1`）で `bundle exec rspec spec/matrix` を流して比べた。落ちた example の集合（`full_description`）は、6 つとも前と後で同じだった。

| 壊したもの | 前 | 後 | 落ちた example |
|---|---|---|---|
| なし | 0 | 0 | — |
| R1 `invoices` の RLS を `DISABLE` にする | 20 | 20 | 表の行列の `invoices` の 5 ペルソナ × 4 |
| R2 `shipments` の `partner_read` から `partnership_active` を外す | 2 | 2 | 表の行列の `shipments`・`shipment_lines` の `revoked_buyer` の読み |
| R3 `stocks` の `owner_write` の `WITH CHECK` を `true` にする | 0 | 0 | — |
| C1 `Sales::ItemPolicy` の `published_catalog` から `view_catalog?` を外す | 1 | 1 | 入口の行列の `SupplierPartnership.catalog` の `ungranted_buyer` |
| C2 `Purchasing::Ordering.place` から `place_orders` の確かめを外す | 4 | 4 | 入口の行列の `Mutation.placePurchaseOrder` の 4 ペルソナ |
| C3 `Partnerships::Access.permitting_suppliers` から権限の絞り込みを外す | 1 | 1 | 入口の行列の `PurchaseOrder.supplierShipments` の `ungranted_buyer` |

R3 は前も後も落ちない。factory の INSERT は `RETURNING` を付けるので、新しい行が SELECT のポリシーでも拒まれ、同じ例外になる。`RETURNING` を付けない INSERT は通ることを psql で確かめ、IB-30 に積んだ。

request spec の補助は、応答をそのまま返す 7 本（`audit`・`catalog`・`inventory`・`part_mappings`・`partnerships`・`purchase_orders`・`shipping`）の `graphql` を `graphql_body` に、エラーが無いことを確かめて `data` を返す 3 本（`billing`・`cancellations`・`inspections`）の `graphql` を `query` に置き換えた。寄せた補助の本文は、消した定義と同じ文である。`supplier_shipments_spec.rb` の `graphql` と、`graphql_entry_spec.rb` のメールを取る `login_as` は残した。`spec/platform/bullet_spec.rb` の `let(:query)` は、取り込んだ `query` より優先され、同じ spec が通る。入口の行列の手書きのログインも `login_as` にした。

### 確かめたこと

`c9ee7f8` で、Ruby 3.4.11 で共通の完了条件と M36 の完了条件を流した。

```sh
bundle exec rspec spec/matrix                  # 857 examples, 0 failures、約 11 秒（変える前の 201290a は 851 examples、約 400 秒）
for seed in 1 2 3; do bundle exec rspec spec/matrix --order rand --seed $seed || exit 1; done   # 3 回とも 0 failures
bundle exec rspec spec/concurrency/concurrency_helpers_spec.rb spec/concurrency/cleanup_guard_spec.rb spec/requests spec/scenarios   # 0 failures
bundle exec rspec packs/purchasing/spec/public/purchasing/receipt_inspections_spec.rb packs/inventory/spec/public/inventory/adjustment_spec.rb   # 0 failures
test "$(grep -rh "def login_as(user)" spec | wc -l)" -eq 1   # 通る
COVERAGE=1 bundle exec rspec --format progress --format json --out tmp/rspec.json   # 1701 examples, 0 failures
BASE_REF=origin/main bin/check-branch-coverage # 一覧は空
bundle exec rspec --tag concurrency            # 2 回続けて 39 examples, 0 failures
bin/rubocop                                    # no offenses
bin/packwerk check                             # 違反なし
bin/check-structure                            # 終了コード 0
bin/check-open-items --due M36                 # 終了コード 0
bin/check-commit-refs                          # 終了コード 0
bin/test-layers tmp/rspec.json                 # 未分類なし
```

分岐の網羅率の警告は 0 件で、example を足した件数も 0 件である。M36 の差分は計測の対象のファイルを変えていない。

全件の時間（手元、1 回ずつ）：

| | 変える前（`201290a`） | 変えた後 |
|---|---|---|
| `COVERAGE=1` | 1688 examples、534 秒 | 1699 examples、70.3 秒（`827a4f1`）。1701 examples、約 71 秒（`c9ee7f8`） |
| 計測なし | — | 1699 examples、64.6 秒（`827a4f1`） |

分岐の計測ありとなしの差は約 6 秒（IB-01 の費用）。

CI の test のジョブ（Run tests の時間は括弧の中）：

| | 時間 |
|---|---|
| 変える前：#39（`cycle-02-end`） | 12 分 27 秒（11 分 22 秒） |
| 変える前：#40（`cycle-03-plan`） | 12 分 05 秒（11 分 02 秒） |
| 変えた後：#41 の 1 回目（`c1f7cc1`） | 2 分 18 秒（1 分 17 秒） |
| 変えた後：#41 の 2 回目（`b680952`） | 2 分 51 秒（1 分 46 秒） |
| 変えた後：#41 の 3 回目（`b680952` の流し直し） | 2 分 36 秒（1 分 31 秒） |

Run tests の 3 回の中央値は 1 分 31 秒で、完了条件の 4 分以下を満たす。

### 残件の処理

引当先が M36 の `open` は無かった。実装で決めたことは OI-85〜OI-87 に judgment で積んだ。表の行列が `WITH CHECK` だけの緩みを捕まえないことは IB-30 に積んだ。

## M25 請求書の発行と受領請求書

PR #43（`m25-invoice-issue`、base は `main`）。PR #42（M36）が未マージなので、M36 の commit も差分に見える。1 回目は、どちらの系統も Conditional Go で、子の表のトリガーが確定を待たない同じ High を出した。High を直して読み直しに出し、どちらの系統も Go になった。1 回目は `250f934..2fe900c` の diff を `2fe900c` の版で、読み直しは `2fe900c..8d4a333` の diff を `8d4a333` の版で読んだ。Codex はどちらもテストを流さず、依頼に書いた実行結果を前提にした。Claude は 1 回目に `2fe900c` の worktree を読み、High の再現と直し方の案を別名の一時 DB で確かめた（消した）。

| 系統 | 1 回目 | 読み直し |
|---|---|---|
| Codex | Conditional Go | Go |
| Claude | Conditional Go | Go |

1 回目の観点ごとの結果：

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘なし |
| 正しさ | 指摘（X1） | 指摘（H1） |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（X2・X3・X4） | 指摘（M1・L1） |
| 参照の維持 | 指摘（X1 に付随） | 指摘（L2） |

読み直しは、どちらの系統も 5 つの観点がすべて指摘なしで、前の High は解消した。

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex・Claude | X1・H1：子の表のトリガーが `issued_at IS NOT NULL` を条件に入れた `EXISTS (... FOR SHARE)` で請求書を引く。READ COMMITTED では、確定がコミットしていない請求書は下書きに見えてロックの前に条件で外れ、確定を待たずに明細の書き換えを通す。data-model.md・マイグレーションのコメント・OI-88 の「確定のコミットを待つ」が成り立たない | 結んだ請求書の行を、条件を付けずに `FOR SHARE` でロックしてから `issued_at` を確かめる形にした（マイグレーションはまだ main に無いので、同じマイグレーションを直した）。data-model.md と OI-88 の説明を直した形に合わせた | `7dd567c`・`8d4a333` |
| Medium | Codex | X2：トリガーと確定の競合を確かめるテストが無い | `closing_lock_spec.rb` に、確定を開いたままの結んだ明細の書き換え・未請求の明細を結ぶ書き換えと、書き換えが先の確定の 3 件を足した。直す前の形と、共有ロックを外した形の両方で 3 件とも落ちる | `7dd567c` |
| Medium | Codex・Claude | X3・L1：失敗の example が、番号を振る前の失敗しか通らない | 「請求書発行」の登録を 1 回だけ失敗させ、番号と確定とイベントが戻り、次の確定が `INV-000001` を振る example を足した | `7dd567c` |
| Medium | Codex | X4：受け手の同時配送を確かめていない。逐次の共有テストは、事前の存在確認に替えても通る | `packs/purchasing/spec/concurrency/purchasing/billing_event_receiver_lock_spec.rb` を足した。受け手を「存在を確かめてから ON CONFLICT の無い INSERT」に替えると、この spec が落ち、逐次の共有テストは通る | `7dd567c` |
| Medium | Claude | M1：行列の member の「何も書かない」が行数だけを比べるので、既存の行を書き換えるだけの mutation を捕まえない | 表ごとに行数と行の中身の要約（`md5(string_agg(t::text ...))`）を比べる形にした。計画の作るもの 4 と OI-90 も合わせた | `7dd567c`・`8d4a333` |
| Low | Claude | L2：`graphql-schema.md` の表が、まだ無い `Sales::ItemPolicy#change_price?` を挙げる | 直さない。計画の M27 の節がその行を指しており、OI-80 の方針（人が読む表を M25 で合わせ、実装は M27）どおりである | — |
| Low | Claude（読み直し） | 後始末のコメントが、止めた状態がほかの接続に見えない理由をロックで書いている | カタログの変更がコミットまで見えないことで書き直した | `6f76792` |
| Low | Claude（読み直し） | UPDATE で OLD と NEW の請求書が同じとき、同じ行を 2 回 `FOR SHARE` で引く | 直さない。正しさに影響せず、同じトランザクションの 2 回目のロックは待たない | — |

違和感は次のように扱った。

- Claude 1：発行日を含む業務の日付が UTC で決まり、「自社の日付」と食い違う → IB-32 に積んだ
- Claude 2：後始末が表のユーザーのトリガーをすべて止める → トリガーを名前で止める形にした（`7dd567c`）
- Claude 3：同じ受注側の確定は、採番の行ロックで取引先が違っても直列になる → IB-33 に積んだ
- Claude 4：S1 の `BuyerView.receivedInvoice(id)` の行が、自社の行が返ることを先に確かめていない → 移さない。1 件を引く入口の行は対照を求めない（`guides/testing.md`「S1 の入口の列挙」）。値を返すことは入口の行列の `only(:granted_buyer)` と `spec/requests/billing_spec.rb` が確かめる
- Codex：なし

### 実装の記録

新しい spec と、`admin` で呼ぶ形に直した request spec を、実装の前に流した。受け手と受領請求書の spec は `Purchasing::BillingEventReceiver`・`Purchasing::ReceivedInvoices` が無い `NameError` で読み込みの時点で落ち、残りは 148 examples, 66 failures だった。失敗は、確定の公開 API・`issueInvoice`・トリガー・新しい表・policy の `admin` が無いことによる。S1 は準備で確定を呼ぶので全行が落ち、確定の競合テストは後始末に渡す表が無くて落ちた。`inspections_spec.rb`・`cancellations_spec.rb` は使うユーザーを `admin` に替えただけなので、書いた時点で通った。行列の役割の列は、policy を直した後に、規則から `user.admin?` を外して落ちることで確かめた。

検出力は壊して確かめた。壊したファイルは複製から戻して更新時刻を進め、テスト DB で壊したものは `db:test:prepare` で戻した。

| 対象 | 壊して落ちること |
|---|---|
| 役割 | `issue?` から `user.admin?` を外すと、行列の `issueInvoice` の member の行・policy の spec・request spec の member の確定が落ちる。`review?` では行列の承認・却下の 2 行と policy の spec、`set_term?` では行列の 1 行が落ちる。`allocate?` を `admin` に限ると、行列の「member にも value」と policy の spec が落ちる。行列の行から `role:` を外すと、行の役割の検査が落ちる |
| 「何も書かない」 | GraphqlController のロールバックを外し、規則の評価を `perform` の後にして監査の行も書かないようにすると、対象を引く `admin` の mutation の member の行が、中身の要約では 10 件、行数だけでは 5 件落ちる。対象を引かない 3 つ（`establishPartnership`・`setBillingTerm`・`closeBillingPeriod`）は規則を `perform` の前に評価するので、この壊し方では落ちない |
| 確定 | 請求条件の行ロックを外すと確定と締めの競合が、請求書の行ロックも外すと確定の競合 3 件が落ちる。発行済みの `CONFLICT` を外すと単体と結合が、「請求書発行」を出さないと単体・結合・S5 が落ちる |
| トリガーと制約 | テスト DB で、請求書のトリガーを素通しにする・子の表の OLD か NEW の確かめを外す・`received_invoices` の CHECK 制約を外す、でそれぞれ `spec/db/issued_invoice_spec.rb` が落ちる。子の表のトリガーを直す前の形に戻すか共有ロックを外すと、確定と明細の書き換えの競合 3 件が落ちる |
| 受け手 | 冪等の見出しの判定を外すと逐次の共有テストが、存在の確かめに替えると同時の配送の競合テストが落ちる |
| 後始末 | トリガーを止めない・止めたトリガーを戻さない、で `concurrency_helpers_spec.rb` の確定した請求書の後始末が落ちる。止めない形では、確定した請求書を残す競合テストも後始末で落ちる |

計画からの細部の決定は台帳に積んだ。トリガーの細部を OI-88、行列で member の行も member で呼ぶことと中身の要約で比べることを OI-90、確定と受領請求書の細部を OI-92 に judgment で積んだ。OI-80 の案 B を表に反映したときに見つけた、`saveItem` から `member` が単価を改定できる経路は OI-89 に blocked-user（M27）で、`startImport` の役割をどこで確かめるかは OI-91 に open（M29）で積んだ。

### 確かめたこと

`8d4a333` で、Ruby 3.4.11 で共通の完了条件と M25 の完了条件を流した。`6f76792` はコメントだけの変更である。

```sh
bundle exec rspec packs/billing/spec/public/billing/closing_spec.rb packs/purchasing/spec/public/purchasing/billing_event_receiver_spec.rb \
  packs/purchasing/spec/public/purchasing/received_invoices_spec.rb packs/sales/spec/public/sales/sales_order_policy_spec.rb \
  packs/purchasing/spec/public/purchasing/purchase_order_policy_spec.rb packs/billing/spec/public/billing/invoice_policy_spec.rb \
  spec/requests/billing_spec.rb spec/requests/inspections_spec.rb spec/requests/cancellations_spec.rb \
  spec/scenarios/billing_amounts_spec.rb spec/scenarios/tenant_boundary_spec.rb   # 0 failures
bundle exec rspec packs/billing/spec/concurrency/billing/closing_lock_spec.rb packs/purchasing/spec/concurrency/purchasing/billing_event_receiver_lock_spec.rb   # 0 failures
bundle exec rspec spec/matrix spec/graphql/authorization_declarations_spec.rb spec/db   # 0 failures
COVERAGE=1 bundle exec rspec --format progress --format json --out tmp/rspec.json   # 1863 examples, 0 failures、80.0 秒
BASE_REF=origin/main bin/check-branch-coverage # 一覧は空
bundle exec rspec --tag concurrency            # 2 回続けて 48 examples, 0 failures
bin/rubocop                                    # no offenses
bin/packwerk check                             # 違反なし
bin/check-structure                            # 終了コード 0
bin/check-open-items --due M25                 # 終了コード 0
bin/check-commit-refs                          # 終了コード 0
bin/test-layers tmp/rspec.json                 # 未分類なし。単体 303・結合 164・シナリオ 83
```

分岐の網羅率の警告は 1 件で、example を足した件数は 0 件である。受け手の明細が空のときの `return` を、どの example も通らなかった。締めは明細が 0 件なら請求書を作らないので届かず、Rails 8.1 の `insert_all!` は空の配列で何もしない（`active_record/insert_all.rb` の `return ActiveRecord::Result.empty if inserts.empty?`）ので、分岐ごと消した。

行列の時間（M36 の完了条件と同じコマンド、手元）：`bundle exec rspec spec/matrix` は 963 examples、12.8 秒（M36 の後は 857 examples、約 11 秒）。足した 106 examples は、member の行と、新しい表と入口の行である。`--order rand --seed 1/2/3` も 3 回とも 0 failures。

CI の test のジョブ（Run tests の時間は括弧の中）：

| | 時間 |
|---|---|
| #43 の 1 回目（`2fe900c`） | 3 分 07 秒（1 分 58 秒） |
| #43 の 2 回目（`6f76792`） | 2 分 59 秒（2 分 05 秒） |

### 残件の処理

引当先が M25 の `open` は無かった。OI-71〜OI-73・OI-77 は作者の判断どおりに実装し、OI-84 は judgment のまま実装した。OI-80 は、`context-map.md`「自社の中の役割」と `graphql-schema.md`「役割による制限」の表を案 B に合わせ、結果の欄の反映先を直した。

## M26 ダッシュボードと失効の通し試験

PR #44（`m26-dashboard`、base は `main`）。PR #42（M36）と #43（M25）が未マージなので、その commit も差分に見える。どちらの系統も Go で、Critical と High は無かった。Medium と Low は同じブランチの commit で直し、違和感は改善の候補に移した。High 以上が無いので、読み直しには出していない。どちらの系統も、`047c3f5..9188951` の diff を `9188951` の版で読んだ。Codex はテストを流さず、依頼に書いた実行結果を前提にした。Claude は `9188951` の worktree を別名のテスト DB で流し、どちらの受け手からアドバイザリロックを外しても競合テストが落ちることと、画面の問い合わせの複雑度と graphql 2.6.11 の原文を確かめた（worktree と DB は消した）。

| 系統 | 判定 |
|---|---|
| Codex | Go |
| Claude | Go |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘なし |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘（L2） |
| テストの検出力 | 指摘（X1） | 指摘（L1・L3） |
| 参照の維持 | 指摘（X2・X3） | 指摘なし |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | X1：クエリ数の予算の spec の `more_lists` の確かめを外しても、落ちる example が無い | 一覧の確かめを `expect_lists` に切り出し、2 つ目の一覧の件数か入れ子が食い違う応答で落ちるガードを足した。`more_lists` を確かめから外すと、このガードが落ちる | `4b19868` |
| Low | Codex | X2：graphql-schema.md の複雑度の数え方が、版を固定した原文を指していない | graphql 2.6.11 の `field.rb` への版を固定した参照と、`first` の無いときの件数の式を添え、掛け算の対象がコネクションの要素であることを書いた | `4b19868` |
| Low | Codex・Claude | X3・Claude の違和感 3：showcase.md テーマ 6 が、本物のスキーマで入れ子のコネクションが拒否されると読める | spec の中で作ったスキーマで確かめることと、リストの下のコネクションはクエリ数の予算の spec が外すことを書いた | `4b19868` |
| Low | Claude | L1：複雑度の spec が、必須の変数を欠いた妥当でない問い合わせ（`BuyerSupplierCatalog`）を計っている | 必須の ID の変数に値を入れ、計る前に `static_errors` が空であることを確かめる形にした。値の決め方の無い必須の変数と、妥当でない問い合わせで落ちる example を足した。`static_errors` の確かめを外すと、この example が落ちる | `4b19868` |
| Low | Claude | L2：リゾルバが受注の一覧の規則だけを評価し、4 つの一覧の規則が同じ答えを返す前提を確かめるテストが無い | `dashboard_spec.rb` に、4 つの policy の `list?` が `admin`・`member` でどれも真であることと、リゾルバの規則が `Sales::SalesOrderPolicy#list?` であることを確かめる example を足した。`Billing::InvoicePolicy#list?` を `admin` に限ると落ちる | `4b19868` |
| Low | Claude | L3：`Sales::SalesOrderStatus::ALL` と導出のつながりを確かめるものが無い | `dashboard_spec.rb` に、`count_by_status` の状況が GraphQL の `SalesOrderStatus` の値とそろう example を足した。`ALL` から 1 つ外すと落ちる | `4b19868` |

違和感は次のように扱った。

- Claude 1：ダッシュボードが、受注と在庫の件数に比例して読み込む → IB-34 に積んだ
- Claude 2：ダッシュボードの今日だけが、リゾルバに `Asia/Tokyo` を直に書いて決まる → IB-32 に書き足した
- Claude 3：showcase.md テーマ 6 の書き方 → X3 と同じ直しで片付けた
- Claude 4：`shipping_hold_lock_spec.rb` は、ロックを外すと `blocked_on_lock?` で落ち、停止中の受注に有効な出荷指示が残る害そのものは spec の中で再現しない → 移さない。計画の「直列にしたなら、勧告ロックを外すと落ちる」を満たし、害の再現は下の実装の記録と OI-79 の結果に書いた
- Codex：自社の行だけを返す公開 API では、scope を外しても RLS が他社の行を隠すので、他社の行を数えない単体の spec が落ちない → IB-35 に積んだ

### 実装の記録

4 つの公開 API の単体の spec を、実装の前に流した。10 examples, 10 failures で、どれもメソッドが無い `NoMethodError` だった。`dashboard_spec.rb` は入口と型を書いた後に書いたので、書いた時点で通った。`supplier.dashboard` を外すと、`dashboard_spec.rb`・行列・クエリ数の予算の 12 件が落ちる。`revocation_spec.rb` は、M8〜M25 で作った振る舞いを通しで確かめるので、書いた時点で通った。`query_complexity_spec.rb` も、画面の問い合わせがどれも上限に収まるので、書いた時点で通った。

OI-79 は、競合テストを先に書いて流し、1 example, 1 failure だった。出荷可能の受け手が停止のコミットを待たずに終わった。同じ順の試しの spec では、停止の受け手を開いたままにしている間に出荷指示の作成が成功し、コミットの後に「解除されていない停止があり、有効な出荷指示が 1 件ある」状態が 3 回とも残った（試しの spec は消した）。停止の受け手と出荷可能の受け手が、出荷依頼を読む前に受注 ID ごとのアドバイザリロックを取る形にして閉じた。

検出力は壊して確かめた。壊したファイルは複製から戻して更新時刻を進めた。

| 対象 | 壊して落ちること |
|---|---|
| 受注の件数 | 0 件の状況を埋めないと単体が落ちる。`ALL` から状況を外すと `dashboard_spec.rb` が落ちる |
| 安全在庫 | 有効在庫を `<=` で比べる・現在庫で比べる、のどちらでも単体が落ちる。品目コードで並べない・上限で切らない、のどちらでも `dashboard_spec.rb` が落ちる |
| 出荷期限 | 出荷済を除かない・取消済を除かない・期限を `<` にする・期限で並べない・上限を外す、のどれでも単体が落ちる |
| 未請求の合計 | 請求書に結んだ明細を足す・合計を整数に戻さない、のどちらでも単体が落ちる |
| 今日 | `Date.current` にすると `dashboard_spec.rb` が落ちる（UTC で 10 月 11 日、日本時間で 10 月 12 日の時刻で流す） |
| 認可 | 請求の一覧の規則を `admin` に限ると `dashboard_spec.rb` が落ちる |
| 複雑度 | `max_complexity` を 300 にすると 8 件が落ちる。`static_errors` の確かめを外すと、妥当でない問い合わせの example が落ちる |
| クエリ数の予算 | `more_lists` を確かめから外すと、ガードが落ちる。負例は、ダッシュボードの 3 つの入れ子のソースを、キーごとに公開 API を呼ぶ形に包んで件数が増えることを毎回確かめる |
| OI-79 | 停止の受け手からも、出荷可能の受け手からも、アドバイザリロックを外すと `shipping_hold_lock_spec.rb` が落ちる |
| S2 | 失効を何もしない形にする・発注の権限の確かめを素通しにする・受領請求書の受け手が取引関係を見る、のどれでも `revocation_spec.rb` が落ちる。発注側の取引関係の scope から「有効な関係」の条件を外しても、RLS が経路 2 を閉じるので落ちない |

公開 API の scope を外しても、4 つの単体は落ちない。4 つの表には相手から読む経路が無く、RLS が他社の行を隠すからである（IB-35）。

計画からの細部の決定は台帳に積んだ。ダッシュボードを認可の例外にしてリゾルバに受注の一覧の規則を使うことを OI-93、安全在庫の並べ替えと上限をルートパッケージで行うことを OI-94、複雑度を `first` の上限で計り、入れ子のコネクションを作ったスキーマで確かめることを OI-95 に judgment で積んだ。OI-95 に合わせて、計画の複雑度の完了条件と `graphql-schema.md`「ページングと N+1」を直した。

### 確かめたこと

`4b19868` で、Ruby 3.4.11 で共通の完了条件と M26 の完了条件を流した。

```sh
bundle exec rspec packs/sales/spec/public/sales/sales_orders_spec.rb packs/inventory/spec/public/inventory/stocks_spec.rb \
  packs/fulfillment/spec/public/fulfillment/shipment_requests_spec.rb packs/billing/spec/public/billing/billable_items_spec.rb \
  spec/requests/dashboard_spec.rb spec/graphql/query_complexity_spec.rb spec/graphql/query_budget_spec.rb spec/matrix   # 0 failures
bundle exec rspec spec/scenarios/revocation_spec.rb                                                       # 0 failures
bundle exec rspec packs/fulfillment/spec/concurrency/fulfillment/shipping_hold_lock_spec.rb               # 0 failures
COVERAGE=1 bundle exec rspec --format progress --format json --out tmp/rspec.json   # 1904 examples, 0 failures、79.9 秒
BASE_REF=origin/main bin/check-branch-coverage # 一覧は空
bundle exec rspec --tag concurrency            # 2 回続けて 49 examples, 0 failures
bin/rubocop                                    # no offenses
bin/packwerk validate && bin/packwerk check    # 違反なし
bin/check-structure                            # 終了コード 0
bin/check-schema-compat                        # 終了コード 0
bin/check-open-items --due M26                 # 終了コード 0
bin/check-commit-refs                          # 終了コード 0
bin/test-layers tmp/rspec.json                 # 未分類なし。単体 313・結合 168・シナリオ 85
```

分岐の網羅率の警告は、最初の全件（`9188951` の前の作業ツリー）で 2 件出て、example を足した件数は 0 件である。安全在庫の並べ替えで品目が無いときの腕と、受注のロックをトランザクションの外で呼んだときの例外の腕を、どの example も通らなかった。在庫の行は自社の品目にだけでき、品目は消さないので前者に届かない。テナントの設定は `Tenancy.with_tenant` のトランザクションの中にだけあるので、後者は `Tenancy.require_tenant!` に替えた。どちらも分岐ごと消した。

行列の時間（手元）：`bundle exec rspec spec/matrix` は 968 examples、14.0 秒（M25 の後は 963 examples、12.8 秒）。足した 5 examples は、`SupplierView.dashboard` の行である。

CI の test のジョブ（Run tests の時間は括弧の中）：

| | 時間 |
|---|---|
| #44 の 1 回目（`9188951`） | 3 分 04 秒（2 分 07 秒） |

### 残件の処理

OI-79 は、起きることを確かめてアドバイザリロックで閉じた（`closed`）。OI-81 は、決めた集計の境界のとおりに実装し、judgment のまま残した。

## M28 外部サービスの呼び出しと非同期の型

PR #45（`m28-external-calls`、base は `main`）。M27 は作者の判断（OI-89）待ちなので、依存の無い M28 を M26 の上に先に積んだ。PR #42（M36）・#43（M25）・#44（M26）が未マージなので、その commit も差分に見える。どちらの系統も Go で、Critical と High は無かった。Medium と Low は同じブランチの commit で直し、違和感は改善の候補に移すか文書を直した。High 以上が無いので、読み直しには出していない。どちらの系統も、`151ffca..2e66ff9` の diff を `2e66ff9` の版で読んだ。Codex は read-only で読み、テストを流さず、依頼に書いた実行結果を前提にした。Claude は `2e66ff9` の worktree を別名のテスト DB で流し、壊して落ちることと、列挙に無い接続の失敗で送信記録が待機中のまま残ることを確かめた（worktree と DB は消した）。Claude の報告によると、壊して確かめる途中で worktree の DB 名の書き換えが戻り、3 回分がテストの DB に流れた。どれもトランザクションを戻すテストで、流した後のテストの DB に残りものは無かった。

| 系統 | 判定 |
|---|---|
| Codex | Go |
| Claude | Go |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（F4） | 指摘なし |
| 正しさ | 指摘（F1） | 指摘（M-1） |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（F1〜F3） | 指摘（L-1） |
| 参照の維持 | 指摘（F4・F5） | 指摘（L-2・L-3） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | F1：同じ送信記録を指す別々の受信の行を 2 つの処理が取ると、両方が時刻列の空を読み、後の処理が先の時刻を上書きする。`SKIP LOCKED` が守るのは受信の行だけである | 処理が送信記録を `FOR UPDATE` でロックしてから時刻列を読む形にした。同じ送信記録・同じ種類・別の時刻の 2 行を 2 つの処理で取り、後の処理が送信記録のロックを待って先の時刻が残る競合テストと、`spec/db/lock_sites_spec.rb` の行を足した。ロックを外すとこの example が落ちる。`adr/007` 決定 5 の A-3 と data-model.md も合わせた | `7db2143`・`031f0fe` |
| Medium | Claude | M-1：列挙に無い接続の失敗（`OpenSSL::SSL::SSLError`・`EOFError`・`Errno::EHOSTUNREACH`・`Errno::ETIMEDOUT`・`Net::HTTPBadResponse`）はジョブから上がり、テナントのトランザクションが戻って、送信記録が試行回数 0 の待機中のまま残る。失敗の時刻も警報も出ず、再送の操作でも拾えない | 再試行する例外に `SystemCallError`・`IOError`・`OpenSSL::SSL::SSLError`・`Net::HTTPBadResponse`・`Net::ProtocolError` を足し、5 つを sendgrid_spec に足した。足した例外を外すと落ちる。ワーカーが落ちたときと、どれにも当たらない例外で残った待機中の送信記録は、運用者が失敗したジョブをやり直して拾うと `adr/007` 決定 5 の A-2 に書いた。計画の例外の列挙を合わせ、OI-102 に judgment で積んだ | `7db2143`・`031f0fe` |
| Medium | Codex | F2：呼び出し元の列挙が、先頭に `::` を付けた `::Notifications::Email.deliver_*` を数えない | 受け手の名前の先頭の `::` を外して比べ、その表記を集めるガードの example を足した。外すと落ちる | `7db2143` |
| Medium | Codex | F3：Webhook のテストの補助が公開鍵の設定を戻すことを確かめるものが無い | 設定と復元を `SendgridWebhookHelpers.with_public_key` に切り出し、通常の終わりと例外の終わりの両方で元に戻ることを確かめる `spec/notifications/sendgrid_webhook_helpers_spec.rb` を足した。`ensure` を外すと 2 件とも落ちる | `7db2143` |
| Medium | Codex・Claude | F4・L-2：計画が「実装する文書の節」に挙げた decisions.md 5 章が、`false` のクラスを `EventJob` だけ、外部へ作用するジョブの基底クラスを仮の名前、`after_commit` からの `deliver_later` を許すと書いたままである | `false` のクラスに `Notifications::CriticalDeliveryJob` を、基底クラスと登録口に `ExternalEffectJob` と `Notifications::Email` を書き、本デモは Action Mailer の `deliver_later` を Cop で禁止すると足した | `031f0fe` |
| Low | Codex・Claude | F5・L-3：config.md の登録の時機を決めるクラスに送信のジョブが無く、「アプリのコードは credentials を読まない」が本番の SendGrid の設定と食い違う | 登録の時機に `ExternalEffectJob` のサブクラスを足し、credentials を読むのは本番の SendGrid の 2 つの値だけと書いた | `031f0fe` |
| Low | Claude | L-1：再送の操作の `where(accepted_at: nil)` を外しても、どの spec も落ちない | 受け付けと失敗の時刻を両方持つ送信記録を spec に足し、送り直さないことを確かめた。条件を外すと落ちる | `7db2143` |

違和感は次のように扱った。

- Claude 1：inbox の処理が行ごとに例外を捕まえず、書けない行が後ろの行を止める → IB-36 に積んだ
- Claude 2：送信のジョブが、DB のトランザクションと送信記録のロックを持ったまま HTTP を呼ぶ → IB-37 に積んだ
- Claude 3：本番で API キーが空でも起動する → IB-38 に積んだ
- Claude 4：`ExternalEffectJob` の TracePoint が、本体が例外で終わると無効にならない → IB-39 に積んだ
- Claude 5：inbox の競合テストが、本番と違ってテナントのある状態で動く → IB-40 に積んだ
- Claude 6：`deliver_critical` の `Tenancy.require_tenant!` は、外しても spec が落ちない → 移さない。宛先の読み取りとテナントの表への書き込みも同じ例外を上げるが、呼び出し元に分かる位置で止めるために残す
- Codex：宛先が複数の送信記録で、1 人にでも届かなければ状況が不達になることが文書に無い → data-model.md「通知（`notifications`）」に、時刻列と状況の意味を 1 文書いた（`031f0fe`）

### 実装の記録

実装と spec を並べて書いたので、テストを先に流して落ちることを見たのは次の 3 つだけである。`sendgrid_spec.rb` は WebMock を入れる前に流して 31 examples, 12 failures で、どれも `stub_request` が無い `NoMethodError` だった。呼び出し元の 2 ファイル（購買の「請求書発行」の受け手と受注の確定）を `151ffca` の版に戻して流すと、23 examples, 5 failures だった（送信記録とジョブが書かれない）。`packs/notifications` のジョブと公開 API の `email.rb`・`inbox.rb` と Webhook のコントローラを外して流すと、spec の読み込みで 6 errors になった。そのほかの spec は書いた時点で通ったので、検出力は壊して確かめた。壊したファイルは複製から戻して更新時刻を進めた。

| 対象 | 壊して落ちること |
|---|---|
| 確実な送信のジョブ | 受け付けか失敗の確かめを外す・送信記録の行ロックを外す・再試行の境界を `<=` にする・429 の待ち時間を使わない・登録の時機を `true` にする・試行回数を書かずに登録し直す・失敗のイベントの名前を変える、のどれでも spec が落ちる |
| 宛先 | `Partnerships::Recipients.admin_ids` が `admin` で絞らないと、確実な送信と撃ちっぱなしの spec が落ちる |
| inbox | `SKIP LOCKED` を外すと競合テストが落ちる（`FOR UPDATE` で待つ）。送信記録のロックを外すと、別の競合テストが落ちる。時刻列を上書きにする・UUID の確かめを外す・1 回のトランザクションの件数で止める、のどれでも単体が落ちる。保持期間を 0 にすると削除の spec が落ちる |
| SendGrid の応答 | 200 を受け付けにしない・接続の時間切れを 60 秒にする・待ち時間を 1 時間で頭打ちにしない・500 を再試行しない・接続の失敗を外す・本番以外の sandbox の確かめを外す・宛先を 1 つの personalization にまとめる、のどれでも落ちる |
| Webhook の受け口 | 残す項目で絞らない・時刻の幅を確かめない・署名を確かめない・書いた行が無くても処理のジョブを登録する、のどれでも落ちる |
| 登録口 | 通知キーの重複でもジョブを登録する・宛先を空にする・再送の `since` の絞り込みや失敗の時刻の消去を外す・本文の値の型や保証の確かめを外す、のどれでも落ちる |
| 宣言と Cop | `ExternalEffectJob` の宣言の確かめを外すと、ガードの example が落ちる。Cop の短い名前の照合を外すと Cop の spec が落ちる。購買の受け手に `CriticalDeliveryJob.perform_later` を足すと `bin/rubocop` が 1 件を出し、`deliver_critical(:received_invoice, ...)` の 2 か所目を足すと `call_sites_spec.rb` が落ちる |
| 設定とテストの基盤 | `Contracts::EventJob` の `queue_as :events` を外す・撃ちっぱなしの同時実行の `group` を外す、のどちらでも `queue_config_spec.rb` が落ちる。`FakeProvider.clear` を外すとジョブの spec が 8 件落ちる。WebMock の遮断を外すと `spec/platform/external_http_spec.rb` が落ちる。競合テストの後始末が送信のジョブを消さないと、`concurrency_helpers_spec.rb` が落ちる |

計画からの細部の決定は台帳に積んだ。送信記録に本文の値を持つことを OI-96、再試行をジョブの中で登録し直すことを OI-97、`new_sales_order` を受注の確定の 1 か所から送ることを OI-98、再送の範囲を OI-99、受信の表に残す項目と署名の時刻の幅を OI-100、宛先の公開 API とテストの送信先の置き場を OI-101、再試行する接続の失敗の範囲を OI-102 に、judgment で積んだ。

計画の「`bin/jobs` を動かして請求書を発行し、`tmp/mails/` に受領請求書の通知が 1 通できる」は、開発の DB に発注側のテナント・`admin`・発注明細を作り、購買の「請求書発行」の受け手を `bin/rails runner` で動かしてから `bin/jobs` を起動して確かめた。`tmp/mails/` に、宛先が `admin`、件名が「請求書が届きました（INV-000042）」の 1 通ができた。scheduler は `process_webhook_inbox`・`purge_webhook_inbox` を登録し、ワーカーは 4 つ起きた。受注側で請求書を発行するところからは流していない。

### 確かめたこと

`7db2143` で、Ruby 3.4.11 で共通の完了条件と M28 の完了条件を流した。

```sh
bundle exec rspec packs/notifications/spec spec/notifications spec/jobs spec/requests/sendgrid_webhook_spec.rb spec/rubocop   # 131 examples, 0 failures
COVERAGE=1 bundle exec rspec --format progress --format json --out tmp/rspec.json   # 2022 examples, 0 failures
BASE_REF=origin/main bin/check-branch-coverage # 4 件（下に書く）
bundle exec rspec --tag concurrency            # 2 回続けて 53 examples, 0 failures
bin/rubocop                                    # no offenses
bin/packwerk validate && bin/packwerk check    # 違反なし
bin/check-structure                            # 終了コード 0
bin/check-schema-compat                        # 終了コード 0
bin/check-open-items --due M28                 # 終了コード 0
bin/check-commit-refs                          # 終了コード 0
bin/test-layers tmp/rspec.json                 # 未分類なし。単体 379・結合 173・シナリオ 89
```

分岐の網羅率の警告は、最初の全件（`2e66ff9` の前の作業ツリー）で 12 件出て、example を足した件数は 6 件である。Cop の受け手の無い呼び出し、Webhook で書く行が 1 つも無いとき（3 件）、`ExternalEffectJob` の保証の誤りと無名のクラスに example を足した。`deliver_critical` のトランザクションの確かめは、テナントがあればトランザクションの中にいるので届かず、分岐ごと消した。撃ちっぱなしの使い切りの腕は、先に残ったジョブで同じ実行の別の example が落ちて通らなかっただけで、example は既にあった。残る 4 件は `ExternalEffectJob` の 37〜41 行で、TracePoint のコールバックの中にある。Ruby はコールバックの中でイベントのフックを止めるので、分岐の網羅率が数えない。宣言の書き忘れで例外になることは、`spec/jobs/event_job_atomicity_spec.rb` が確かめている。

行列の時間（手元）：`bundle exec rspec spec/matrix` は 988 examples、12.3 秒（M26 の後は 968 examples、14.0 秒）。足した 20 examples は `email_deliveries` の表の行である。

CI の test のジョブ（Run tests の時間は括弧の中）：

| | 時間 |
|---|---|
| #45 の 1 回目（`2e66ff9`） | 3 分 13 秒（2 分 12 秒） |
| #45 の 2 回目（`031f0fe`、レビューの指摘を直した後） | 3 分 14 秒（2 分 21 秒） |

### 残件の処理

OI-15 は、SendGrid の文書と sendgrid-ruby で確かめて `adr/007`「確認した事項」に移し、閉じた（`closed`）。OI-83 は、決めた宛先（自社の `admin`）のとおりに実装し、judgment のまま残した。

## M27 販売単価のバイテンポラル履歴

PR #46（`m27-item-prices`、base は `main`）。M28 の上に積んだので、#42〜#45 の commit も差分に見える。着手の前に、作者が OI-89 を案 B に決めた（2026-10-12）。既存の品目の単価を変える入口を `scheduleItemPrice`・`correctItemPrice` だけにし、`saveItem` からは役割を問わず変えられない。どちらの系統も Go で、Critical と High は無かった。Medium と Low は同じブランチの commit で直し、違和感は改善の候補に移すか文書を直した。High 以上が無いので、読み直しには出していない。どちらの系統も、`ca402a1..cb9aa8a` の diff を `cb9aa8a` の版で読んだ。Codex は read-only で読み、テストを流さず、依頼に書いた実行結果を前提にした。Claude は `cb9aa8a` の worktree を別名のテスト DB で流し、完了条件の spec に `spec/concurrency/concurrency_helpers_spec.rb` を足して 1202 examples, 0 failures を確かめた（worktree と DB は消した）。

| 系統 | 判定 |
|---|---|
| Codex | Go |
| Claude | Go |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘なし |
| 正しさ | 指摘（F1・F2） | 指摘（C-1・C-3） |
| 境界と規約 | 指摘（F1・F2） | 指摘なし |
| テストの検出力 | 指摘（F1） | 指摘（C-1・C-4） |
| 参照の維持 | 指摘（F3） | 指摘（C-2） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | F1：トリガーが記録期間の下限の値だけを比べ、端の含み方を見ないので、`[t0,)` を `(t0,t1)` や `[t0,t1]` に変えて閉じる UPDATE と、始まりを含まない行の INSERT が通る | 記録期間を `lower_inc AND NOT upper_inc` の CHECK 制約で限った。端の含み方を変える UPDATE 3 つと始まりを含まない INSERT を拒む example と、訂正の時刻ちょうどの記録時点で訂正の後の行だけを返す example を足した。制約を外すと前者が落ちる。`adr/006` 決定 2 と data-model.md に書いた | `7477684`・`00f92ec` |
| Medium | Claude | C-1：`saveItem` が新しい品目の最初の単価の行に操作者を書かない | `recorded_by_user_id` に操作者を渡し、`catalog_spec.rb` で確かめた。渡さないと落ちる | `7477684` |
| Low | Codex・Claude | F2・C-4：列を消すマイグレーションの down が SQL の `CURRENT_DATE` を使う。止まる条件と down は手で確かめただけで spec が無い | down の今日を `Date.current` にした。移行の spec に、移行の前には止まり、移行の後に通り、巻き戻すと今日の単価を列に戻す example を足した。残りの確かめを外すか、down が単価を戻さないと落ちる | `7477684` |
| Low | Codex・Claude | F3・C-2：graphql-schema.md の行列の説明が「値を返すペルソナの member」のまま。`Item.unitPrice` の出どころが `price_at` と書かれているが、実装は使っていない。`adr/006` 決定 7 の今日の行に絞る場所が policy scope のまま | 行列の説明を OI-107 の形に直した。カタログの今日の単価を `Sales::ItemPrices.price_at` で引く形にし、読み取りの一覧にそう書いた。決定 7 と data-model.md を `Sales::PublishedCatalog` に揃えた | `7477684`・`00f92ec` |
| Low | Claude | C-3：アプリの時計が閉じる行の記録の始まりより前に戻ると、範囲の構築かトリガーで内部エラーになることが文書に無い | `adr/006` 決定 3 に、操作が例外で失敗して何も書かないと書いた。`CONFLICT` には変えていない | `00f92ec` |

違和感は次のように扱った。

- Claude 1：`items.unit_price` を消すときのデプロイの順が、計画の節と OI-106 にしか無い → IB-42 に積んだ
- Claude 2：今日からの改定は、同じ日に受けた受注の `unitPriceNow` を新しい単価にし、説明の上は食い違いに見える → IB-43 に積んだ
- Claude 3：`Scope.item_prices` は所有の条件だけで絞り、品目の可視性を見ない → 移さない。単価の表に渡せる scope の名前は `:own` だけで、品目の列（`published`）を使う `:published_catalog` を渡すと SQL のエラーになり、黙って広がらない
- Codex：なし

### 実装の記録

単体（`item_prices_spec.rb`）・移行（`item_prices_backfill_spec.rb`）・DB（`item_prices_constraints_spec.rb`）の 3 つの spec は、マイグレーションと実装の前に流して、`uninitialized constant Sales::ItemPrices` で読み込みに失敗した。request spec（`spec/requests/item_prices_spec.rb`）は、GraphQL の型と mutation とカタログを M28 の版に戻して流すと 9 examples, 9 failures だった。そのほかの spec は書いた時点で通ったので、検出力は壊して確かめた。壊したファイルは複製から戻して更新時刻を進め、DB の制約はテストの DB を所有ロールで変えてから `bin/rails db:test:prepare` で戻した。

| 対象 | 壊して落ちること |
|---|---|
| 予約と訂正 | 予約が品目をロックしない・訂正がロックの後に行を読み直さない、のどちらでも競合テストが落ちる。同じ単価でも行を分ける・改定日と同じ始まりの行にも前の行を足す・過去の改定日を拒まない・理由の空を拒まない、のどれでも単体が落ちる |
| 単価を引く | 記録時点を見ない・説明の発行の時点にいまの行を使う、のどちらでも単体と request spec が落ちる。発注側のカタログが今日の行に絞らないと request spec が、照合のやり直しが今日の単価を写すと `part_mappings_spec.rb` が落ちる |
| saveItem | 既存の品目の単価を確かめない・品目を書いてから単価を確かめる・新しい品目に単価の行を足さない・最初の単価の行に操作者を書かない、のどれでも落ちる。品目を書いてから確かめると、入口の行列の member の example が「何も書かない」で落ちる |
| 規則 | `change_price?` が `admin` を確かめないと、行列と request spec が落ちる |
| 移行 | 行のある品目を飛ばさないと移行の spec が落ちる。列を消すマイグレーションが残りを確かめない・down が単価を戻さない、のどちらでも落ちる。品目のテナントで絞らないことは落ちない。テナントの中では RLS が同じ条件を持つからで、所有の条件を明示する規約として残した |
| DB | テストの DB でトリガーを外すと `item_prices_constraints_spec.rb` が 4 件、排他制約を外すと 1 件、記録期間の端の CHECK 制約を外すと 1 件落ちる。`partner_read` を外すと表の行列が 2 件落ちる。`partner_read` から `upper_inf` を外しても表の行列は落ちない（世界の公開品目は閉じた行を持たない）ので、`item_prices_rls_spec.rb` を足した。外すとこれが落ちる |
| テストの基盤 | 競合テストの後始末が単価の行のトリガーを止めないと、`concurrency_helpers_spec.rb` の足した example が落ちる。移行の spec が足し直した列を消し忘れると、ファイルの終わりの `after(:context)` が落ちる |

計画からの細部の決定は台帳に積んだ。`saveItem` の同じ単価を無視することを OI-103、記録の時刻をロックの後のアプリの時刻にしたことを OI-104、有効日の今日を受注日と同じ `Date.current` にしたことを OI-105（業務の日付を日本時間に揃えるかは IB-41）、列を消すマイグレーションと移行の spec の形を OI-106、入口の行列の広げ方を OI-107、予約の何も書かない範囲と記録時点の既定を OI-108 に、judgment で積んだ。

計画の「移行のタスク → 列を消すマイグレーション」は、開発の DB で確かめた。移行の前の形の品目と照合済みの明細を作ると、列を消すマイグレーションが「現在の単価の行が無い品目か、priced_on の無い照合済みの明細が 2 件ある。先に bin/rails sales:backfill_item_prices を流す」で止まり、タスクが品目 1 件と明細 1 件を写した後に通った。タスクを 2 回目に流すと 0 件で、巻き戻すと `items.unit_price` に今日の単価（250）が戻った。

### 確かめたこと

`00f92ec` で、Ruby 3.4.11 で共通の完了条件と M27 の完了条件を流した。

```sh
bundle exec rspec packs/sales/spec spec/matrix spec/requests/item_prices_spec.rb   # 1196 examples, 0 failures
COVERAGE=1 bundle exec rspec --format progress --format json --out tmp/rspec.json   # 2147 examples, 0 failures
BASE_REF=origin/main bin/check-branch-coverage # 4 件（下に書く）
bundle exec rspec --tag concurrency            # 2 回続けて 56 examples, 0 failures
bin/rubocop                                    # no offenses
bin/packwerk validate && bin/packwerk check    # 違反なし
bin/check-structure                            # 終了コード 0
bin/check-schema-compat                        # 終了コード 0（非破壊の変更だけ）
bin/check-open-items --due M27                 # 終了コード 0
bin/check-commit-refs                          # 終了コード 0
bin/test-layers tmp/rspec.json                 # 未分類なし。単体 422・結合 182・シナリオ 94
```

分岐の網羅率の警告は、M27 の差分では最初の全件（`3f60248` の前の作業ツリー）で 2 件出て、example を足した件数は 1 件である。`ItemPrice#close!` の閉じた行の腕に example を足した。`BillableItemType#price_explanation` の請求書が見えない腕は、請求対象明細が見えれば結んだ請求書も見えるので届かず、`&.` ごと消した。残る 4 件は M28 の `external_effect_job.rb` の TracePoint のコールバックの中の行である（「M28」の節）。

行列の時間（手元）：`bundle exec rspec spec/matrix` は 1052 examples、13.5 秒（M28 の後は 988 examples、12.3 秒）。足した 64 examples は、`item_prices` の表の行と、2 つの mutation の行と、`member` に許す mutation を全ペルソナの `member` で呼ぶ行である。

CI の test のジョブ（Run tests の時間は括弧の中）：

| | 時間 |
|---|---|
| #46 の 1 回目（`cb9aa8a`） | 2 分 58 秒（2 分 6 秒） |
| #46 の 2 回目（`00f92ec`、レビューの指摘を直した後） | 3 分 16 秒（2 分 19 秒） |

### 残件の処理

OI-89 は作者の判断（案 B）で閉じた（`decided`）。OI-80 は、作者の判断のとおり `scheduleItemPrice`・`correctItemPrice` を `admin` に限って実装した（`Sales::ItemPolicy#change_price?`）。引当先が M27 の `open` と `blocked-user` は残っていない。
