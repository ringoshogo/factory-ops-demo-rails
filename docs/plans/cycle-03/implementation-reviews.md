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
