# サイクル 5 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M38 RLS の UPDATE のポリシーが隠す所有の条件を、単体で捕まえる

PR #56（`m38-update-policy`、base は `main`）。PR #55（`cycle-05-plan`）が未マージなので、その commit も差分に見える。M38 の差分は `99936b6..` である。

Codex は Go、Claude は Conditional Go で、Medium の M38-1（出荷停止の解除の upsert が届く形なのに、届かない形に数えている）を直せば Go とした。どちらの系統も、`99936b6..ff2a08e` の diff を `ff2a08e` の版で読んだ。Codex は read-only のサンドボックスでテストを流さず、依頼に書いた実行結果を前提にした。Claude は `ff2a08e` を `git archive` で展開したコピーで、所有の条件と文脈の基盤を壊して確かめた。Critical・High が無かったので、読み直しは回していない。指摘は `2439379` で直した。

| 系統 | 判定 |
|---|---|
| Codex | Go |
| Claude | Conditional Go |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R1） | 指摘（M38-2） |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘（M38-1） |
| テストの検出力 | 指摘（R1・R2） | 指摘（M38-1） |
| 参照の維持 | 指摘（R3） | 指摘（M38-3） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Claude | M38-1：`Fulfillment::SalesEventReceiver` の出荷停止の解除（`release_hold`）は `ON CONFLICT DO UPDATE` で、テナントをまたぐ審査 ID の一意索引が他社の行に導くのに、`testing.md` は「冪等キーにグローバルな一意索引がある受け手」として届かない形に数えている。他社の行への書き込みを止めているのは RLS だけである | 更新の `WHERE` に所有の条件を書き、他社の行に当たったら `RecordNotFound` で失敗させた（OI-152）。文脈の describe に、他社の同じ審査 ID の停止を置いて解除を渡す example を足した。`testing.md` の届かない形から解除を外し、`ON CONFLICT DO UPDATE` の書き方を書いた | `2439379` |
| Medium | Codex | R1：出荷取消の example は自社の停止を用意せず、停止を解除する `update_all` を消しても通る。安全在庫は成功の返り値だけ、セッションの失効は件数だけで、自社の行の書き込みを確かめていない | 出荷取消の example で、審査 ID を空にしたまま自社の停止を置き、解除されることを確かめた。安全在庫とセッションの失効は、自社の行を読み直して値を確かめた | `2439379` |
| Medium | Codex | R2：重なりの失敗の 2 つの example は両方のポリシーを全表に置いてから足し直すので、最初の SELECT のポリシーで失敗し、UPDATE のポリシーの重なりと、足しかけたポリシーの巻き戻しを確かめない | 最後の表に UPDATE のポリシーだけを置いてから足す example を足した。失敗した後に、足しかけた 2 つのポリシーが残らず、置いたポリシーが残ることを確かめる。失敗の経路の数え方を、2 つの名前ごとの数にそろえた（Claude の違和感 2 も同じ直し） | `2439379` |
| Low | Claude | M38-2：完了条件の行列の 2 ファイルの時間が、変える前と後で記録されていない | 下の「確かめたこと」に書いた | この記録と同じ commit |
| Low | Claude・Codex | M38-3・R3：M40 の節・依存の表・`spec/support/matrix_world.rb` のコメント・`matrix_world_spec.rb` の describe に、文脈の古い名前と SELECT だけを開く説明が残る | 4 か所を直した。`git grep '「RLS の SELECT を開く」'` の残りは、サイクル 04 の記録と、M38 の節の目的（直す前の形の説明）だけである | `2439379` |

違和感は次のように扱った。

- Claude 1：集める対象の境界が書かれていない（パッケージの中のジョブが ID だけで行をロックして書く） → 下の「集めた箇所」の表の後に外した理由を書き、操作者のいる mutation の公開 API の同じ形とあわせて IB-71 に積んだ
- Claude 2：失敗の経路のガードが SELECT のポリシーの数しか数えない → R2 の直しで、2 つの名前ごとの数にした
- Claude 3：各 example の対照の注記が SELECT の側だけを言う → 他社の行が UPDATE の対象に入ることは、`cross_read_spec.rb` のポリシーの形の確かめが持つ。注記は直さない
- Claude 4：`runs_spec.rb`・`authentication_spec.rb`・`recipients_spec.rb` の読み取りの example の名前が「RLS の SELECT を開いても」のまま → 読み取りの確かめなので名前どおりである。直さない
- Codex 1：単価の移行の example は、所有ロールで個別の列を読み、全属性を比べない → 例ごとのトランザクションを使わない spec で、他社の明細は所有の列と書く列（`priced_on`）で足りる。直さない
- Codex 2：行列の 2 ファイルの時間が無い → M38-2 と同じ
- 実装者：worktree では `bin/ci` の Setup の工程が落ちる（下の「確かめたこと」） → IB-72 に積んだ

### 実装の記録

#### 試作と分かれ目

作るもの 1 の試作を、別名の DB（`factory_ops_demo_rails_test_m38proto`）で、所有ロールで作った一時の表に `owner_write` と同じポリシー・SELECT のポリシー・UPDATE のポリシー（`WITH CHECK (false)`）を置き、アプリのロールの psql で流した。所有の移し替えは通るが、同じ接続で読み直すと所有の列の変化が見えるので、対照で捕まえられる。判断の裏返る条件には当たらなかったので、既定の推奨（UPDATE のポリシーを開く形）で進めた。試作の DB は消した。

| 流した文（自社のテナントの設定で、他社の行に） | 設定が `off` | 設定が `on` |
|---|---|---|
| 所有の列を変えない UPDATE | 0 行 | RLS の違反（`WITH CHECK`） |
| 所有の列を自社に書き換える UPDATE | 0 行 | 通る。同じ接続で読み直すと所有の列が自社に変わっている |
| 所有の列を書き換える `INSERT ... ON CONFLICT DO UPDATE` | RLS の違反（`USING`） | 通る。読み直すと所有の列が自社に変わっている |
| 所有の列を変えない `INSERT ... ON CONFLICT DO UPDATE` | — | RLS の違反（`WITH CHECK`） |
| `SELECT ... FOR UPDATE` | 0 行 | 他社の行をロックする |
| DELETE | — | 0 行 |
| 他社の名義の INSERT | — | RLS の違反 |
| 自社の行の UPDATE／自社の行を他社の名義にする UPDATE | — | 通る／RLS の違反 |

#### 集めた箇所

操作者のいない入口の公開 API は、`graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」の入口の種類（ジョブ・rake タスク・イベントの受け手・認証）から、rake タスクとジョブと認証が呼ぶ公開 API をたどって集め、サイクル 04 の M32 の一覧と照らした。イベントの受け手は配送表（`Contracts::Subscriptions::TABLE`）の 7 つである。計画が名指しした `Inventory::Stocks.set_safety_stock`（シードの準備の公開 API で、GraphQL の入口が無い）も入れた。その中で UPDATE・`update_all`・FOR UPDATE・`ON CONFLICT DO UPDATE` で行を引く箇所に、example を足した。

| 箇所 | 引き方 | example（spec） |
|---|---|---|
| `Notifications::Email.redeliver_failed` | FOR UPDATE と `update!` | `email_spec.rb`「他社の失敗した送信記録を送り直さず、変えない」 |
| `Partnerships::Authentication.revoke_sessions` | `update_all` | `authentication_spec.rb`「RLS の SELECT と UPDATE を開いても、他社のユーザーのセッションを失効させない」 |
| `Inventory::Stocks.set_safety_stock` | scope と FOR UPDATE | `stocks_spec.rb`「他社の品目は NOT_FOUND で、他社の在庫を書かない」 |
| `Sales::ItemPrices.backfill` の明細 | UPDATE | `item_prices_backfill_spec.rb`（既存の example を UPDATE も開く形の名前にした） |
| `Imports::Files.purge_abandoned` | FOR UPDATE と `update_all` | `purge_abandoned_files_job_spec.rb`「他社の置いたままのファイルを数えず、変えない」（OI-151） |
| `Sales::FulfillmentEventReceiver` の出荷計上 | FOR UPDATE と `update!` | `fulfillment_event_receiver_spec.rb`「他社の受注は見つからず、書かない」 |
| `Sales::PurchasingEventReceiver` の取消依頼 | FOR UPDATE と審査の INSERT | `purchasing_event_receiver_spec.rb`「他社の受注は見つからず、審査を作らない」 |
| `Sales::PurchasingEventReceiver` の検収完了 | FOR UPDATE と記録の INSERT と `update!` | 同「他社の出荷済の受注は見つからず、検収を記録せず、受注を書かない」 |
| `Purchasing::SupplierEventReceiver.handle` | FOR UPDATE と `update!`（どの種類も同じ 1 か所で引く） | `supplier_event_receiver_spec.rb`「他社の発注は見つからず、書かない」 |
| `Fulfillment::SalesEventReceiver` の出荷取消の出荷依頼 | FOR UPDATE と `update!` | `sales_event_receiver_spec.rb`「出荷取消は、他社の受注の出荷依頼と出荷停止を書かない」（OI-150） |
| `Fulfillment::SalesEventReceiver` の出荷取消の出荷停止 | `update_all` | 同上 |
| `Fulfillment::SalesEventReceiver` の出荷停止の解除（`release_hold`） | `ON CONFLICT DO UPDATE` | 同「出荷停止解除は、他社の同じ審査 ID の出荷停止を書かずに失敗する」（実装レビューの M38-1 で足した、OI-152） |

届かない形として example を足さなかったもの：出荷依頼の作成と出荷停止の記録（`Fulfillment::SalesEventReceiver`）、受注の連結（`Sales::PurchaseOrderTranslator`）、請求対象の記録（`Billing::SalesEventReceiver`）、受領請求書の記録（`Purchasing::BillingEventReceiver`）は、冪等キーにグローバルな一意索引があり、キーが重なれば書かずに飛ばす。出荷停止の受け手が出荷依頼をロックする箇所は、ロックだけで書かない。どれも `testing.md`「行列テストとの分担」に書いた。読むだけの公開 API（通知の宛先・認証の操作者・取り込みの再登録）は、M32 で足した SELECT を開く example のままである。

パッケージの中のジョブ（`Notifications::CriticalDeliveryJob#perform`・`Notifications::ProcessInboxJob#apply`・`Imports::Chunk.locked`）は、ID だけで行をロックして書き、所有の条件を RLS に任せる。規則は操作者のいない入口から呼ぶ公開 API に掛かり、これらは公開 API でないので、集める対象に入れなかった（IB-71）。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：

- 計画が最初に落とすとした `spec/matrix/cross_read_spec.rb` の `pg_policies` の確かめは、UPDATE のポリシーを足す前に、`got: [["matrix_cross_read", "PERMISSIVE", "SELECT", "(current_setting('app.matrix_cross_read'::text, true) = 'on'::text)", nil, 40]]` で落ちた（`matrix_cross_update` の行が無い）。文脈の名前を変える前は、名前の無い文脈の読み込みの失敗だったので数えず、名前だけを変えてから流し直した
- 実装レビューの M38-1 で足した出荷停止の解除の example は、所有の条件を書く前に `expected ActiveRecord::RecordNotFound, got #<ActiveRecord::StatementInvalid:"PG::InsufficientPrivilege: ERROR:  new row violates row-level security policy for table \"shipping_holds\"">` で落ちた

ほかの example は実装の後に書いたので、次の壊して落ちる記録で RED に代える。壊したファイルは複製から戻し、壊すときと戻すときに更新時刻を進めた。壊した箇所を確かめる spec のファイルだけを流した。ポリシーが残る壊し方の後は、補助の `remove!` で外し、`pg_policies` の `matrix_cross_%` が 0 行に戻ったことを確かめた。

所有の条件（`ff2a08e` の上で 1 つずつ外す。出荷停止の解除だけは `2439379` の上）：

| 壊したもの | 落ちた example | UPDATE のポリシーを足さない補助で同じ壊し方 |
|---|---|---|
| `redeliver_failed` の `owner_tenant_id` | 1（`PG::InsufficientPrivilege`） | 0 failures |
| `revoke_sessions` の `own_users` を `User` に | 1（同上） | 0 failures |
| `set_safety_stock` の scope | 1（同上） | 0 failures |
| `backfill` の明細の `l.owner_tenant_id = $2` | 1（同上） | 0 failures |
| `purge_abandoned` の候補の `owner_tenant_id` | 1（同上） | 0 failures |
| 出荷計上の受注の `owner_tenant_id` | 1（`expected RecordNotFound, got StatementInvalid`） | 0 failures |
| 取消依頼の受注の `owner_tenant_id` | 1（同上） | 0 failures |
| 検収完了の受注の `owner_tenant_id` | 1（同上） | 0 failures |
| 購買の受け手の発注の `owner_tenant_id` | 1（同上） | 0 failures |
| 出荷取消の出荷依頼の `own_requests` を `ShipmentRequest` に | 1（`PG::InsufficientPrivilege`） | 0 failures |
| 出荷取消の出荷停止の `owner_tenant_id` | 1（同上） | 0 failures |
| 出荷停止の解除の `WHERE` の所有の条件 | 1（`expected RecordNotFound, got StatementInvalid`） | — |
| 出荷停止の解除の、当たらなかったときの `raise` | 1（`expected RecordNotFound but nothing was raised`） | — |
| 出荷停止の受け手のロックの `own_requests`（届かない形） | 0 failures | — |

対照（自社の行の書き込みと、所有の移し替え）：

| 壊したもの | 落ちた example |
|---|---|
| `revoke_sessions` を他社の行を自社の名義に書き換える形にし、他社の件数の期待を外す | 1：`reread` の比べで、`owner_tenant_id` と `session_version` が変わる |
| 出荷取消の受注ごとの出荷停止の `update_all` を消す（`2439379` の上） | 1：自社の停止が解除されない |
| 文脈の `cross_read!` を何もしない形にする（Claude のコピー、`ff2a08e`） | 完了条件の 2 つ目のコマンドで 12：足した 11 か所と既存の SELECT の example。`reread` が他社の行を引けない |

補助：

| 壊したもの | 落ちた example |
|---|---|
| UPDATE のポリシーから `WITH CHECK (false)` を外す | 1：`cross_read_spec.rb` の `pg_policies` の形（`with_check` が `nil`） |
| `remove!` が UPDATE のポリシーを外さない | 4：`cross_read_spec.rb` の 3 件と、`tenant_enforcement_spec.rb` のポリシーの集合 |
| `add!` を 1 つのトランザクションにしない（`2439379` の上） | 1：最後の表の UPDATE のポリシーだけが先にある example（`got: {"matrix_cross_read" => 39, "matrix_cross_update" => 40}`） |

### 確かめたこと

`2439379` で、Ruby 3.4.11 で M38 の完了条件と共通の完了条件を流した。この worktree では `bin/ci` の Setup の工程（`bin/setup` の `docker compose up`）が、compose のプロジェクト名が元の作業ツリーと違うので 5433 で別のコンテナを作ろうとして落ちる（`ff2a08e` で `bin/ci` を流して確かめた。ほかの工程はすべて通った）。そのため `2439379` では、`config/ci.rb` の Setup のほかの工程を同じコマンドで 1 つずつ流した。

```sh
bundle exec rspec spec/matrix spec/db/tenant_enforcement_spec.rb   # 1320 examples, 0 failures
bundle exec rspec <完了条件の 2 つ目のコマンド>                    # 104 examples, 0 failures
bin/ci の Setup のほかの工程                                       # すべて通る（rspec は 2628 examples, 0 failures、brakeman は警告 0）。2 分 30 秒
BASE_REF=origin/main bin/check-branch-coverage                     # 一覧は空
bin/check-open-items --due M38                                     # 終了コード 0
bundle exec rspec --tag concurrency                                # 2 回続けて 61 examples, 0 failures
```

試作と完了条件のあとに、`pg_policies` の `matrix_cross_%` が 0 行であることを確かめた。分岐の網羅率の警告は 0 件で、example を足した件数も 0 件である。

行列の spec の時間（手元、`bundle exec rspec <ファイル>` を 2 回ずつ。変える前は `99936b6` を `git archive` で展開したコピーで流した）：

| ファイル | 変える前（`99936b6`） | 変えた後（`2439379`） |
|---|---|---|
| `spec/matrix/graphql_matrix_spec.rb` | 491 examples、7.26 秒・8.18 秒 | 491 examples、7.99 秒・7.37 秒 |
| `spec/matrix/table_matrix_spec.rb` | 804 examples、8.42 秒・7.52 秒 | 804 examples、7.44 秒・7.35 秒 |

2 ファイルを合わせて約 15 秒で、変える前と変わらない。IB-50 の調べ直す条件（合わせて 30 秒を超える）には当たらない。

### 残件の処理

引当先が M38 の行は、着手の前と PR の前に台帳を読み、無かった。実装で決めたことは OI-150・OI-151 に、実装レビューの M38-1 の直しで決めたことは OI-152 に judgment で積んだ。違和感は IB-71・IB-72 に積んだ。範囲外の IB-59（操作者のいない入口の `Tenancy.require_tenant!` が `TenantRecord` の `default_scope` に隠れること）は扱っていない。

## M39 一覧の件数と並べ替え、列での絞り込み

`m39-list-ordering`（base は `main`）の PR。PR #55（`cycle-05-plan`）と PR #56（`m38-update-policy`）が未マージなので、その commit も差分に見える。M39 の差分は `ef7f95d..` である。

Codex は Go、Claude は Conditional Go で、Medium の R1（範囲の外の日付と正しくない UTF-8 のカーソルが 500 になる）を直せば Go とした。どちらの系統も、`ef7f95d..0fcd396` の diff を `0fcd396` の版で読んだ。Codex は read-only のサンドボックスでテストを流さず、依頼に書いた実行結果を前提にし、DB の要らない再現だけを流した。Claude は行列と共有の文脈を使う spec のほかの M39 の spec を流し、`bin/rails runner` でカーソルの 500 を再現した。Critical・High が無かったので、読み直しは回していない。指摘は `870aacb`（コード）と `dc2a367`（文書）で直した。

| 系統 | 判定 |
|---|---|
| Codex | Go |
| Claude | Conditional Go |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R3） | 指摘（R3） |
| 正しさ | 指摘（R1・R2） | 指摘（R1） |
| 境界と規約 | 指摘（R1） | 指摘なし |
| テストの検出力 | 指摘（R1・R2） | 指摘（R1） |
| 参照の維持 | 指摘（R3・R4） | 指摘（R2・R3・R4） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Claude・Codex | Claude R1・Codex R2：カーソルの日付は `Date.iso8601` を通るだけで、PostgreSQL の date の範囲の外の年も受け付ける。文字列は正しくない UTF-8 も通る。どちらも行を読むときの SQL のエラーになり、`Invalid cursor` ではなく 500 を返す | 日付を西暦 1 年から PostgreSQL の date の上限（5874897 年）までに、文字列を正しい UTF-8 に限った。`page_spec.rb` に、範囲の両端と外側（整数の下限を含む）と正しくない UTF-8 の example を足した | `870aacb` |
| Medium | Codex | R1：`Page` のテナントの確かめが `||=` の右辺にあり、一度読んだ値は、テナントの外でも別のテナントの中でも例外にならずに返る | 読むたびにテナントを確かめる形にし、4 つの読み口を外と別のテナントで読む example を足した | `870aacb` |
| Low | Claude | R2：`testing.md`「行列テストとの分担」に、コネクションの行が `totalCount` を読む規則と、絞り込みの変種の行と世界の行の関係が無い | 同じ節の 2 回目の比較の箇条に溶かし込み、世界の説明を直した | `dc2a367` |
| Low | Claude・Codex | R3：`graphql-schema.md` の `Viewer` の SDL に `tenant` が無い。計画の作るもの 6 が、OI-154 と食い違って「相手のテナントの ID で一覧は空」のまま | SDL に `tenant: Tenant!` を書き、作るもの 6 を OI-154 の形に直した。直す前の文言は、`git grep` で計画にも設計文書にも残っていないことを確かめた | `dc2a367` |
| Low | Claude・Codex | R4：`keyword` の `%`・`_` の扱いと大文字と小文字の区別が、`sanitize_sql_like` と Arel の `matches` と DB の既定のエスケープ文字に依存するのに、根拠を引いていない | `matches` に ESCAPE と `case_sensitive: false` を明示し、依存する Arel のメソッドをコメントに引いた | `870aacb` |

違和感は次のように扱った。

- Claude 1：`pageInfo` だけを選んでも値への写しが流れる → IB-73
- Claude 2・Codex 1：件数と行が別の SQL で、同時の書き込みで食い違いうる → IB-74
- Claude 3：リストの要素の下のコネクションの `totalCount` が、親ごとに `COUNT(*)` を流す → IB-75
- Claude 4：有効在庫の定義が 3 か所にある → IB-76
- Codex 2：文字列の並べ替えの照合順序を記録していない → IB-77
- Claude 5：依頼の版に証跡の M39 の節が無く、壊して落ちる記録が依頼の本文にだけあった → IB-78

### 実装の記録

#### 計画との違い

計画に書かれていないことを決めたものは、OI-153〜OI-157 に judgment で積んだ。`Page` が件数だけでなく行も読まれたときに引き、作ったテナントの外で読むと例外にする（OI-153）。発注の受注側の絞り込みの S1 の行は、相手のテナント ID を自社の行の対照にする（OI-154）。予算の spec の受注と発注の `filter` は日付の範囲だけを渡す（OI-155）。`keyword` の前後の空白に全角の空白を含める（OI-156）。並べ替えの入力型の `field` と `direction` をどちらも必須にする（OI-157）。

OI-153 の結果、ページの値をテナントの外で読んでいた 4 つの spec（`invoices_spec.rb`・`received_invoices_spec.rb`・`runs_spec.rb`・`audit_logs_spec.rb`）が `Tenancy::MissingTenant` で落ちたので、値を中で読む形に直した（`aafbb35`）。どの example も、確かめる値は変えていない。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：

- `page_spec.rb` の ASC と DESC の境目の example は、`Page.of` が `sort:` を受け取るだけで無視する仮の形で、`got:` が id の降順のまま落ちた
- `graphql_matrix_spec.rb`「コネクションを返すフィールドの行は、すべて問い合わせで totalCount を読む」は、`got: ["Viewer.auditLogs", "SupplierView.items", "SupplierPartnership.catalog", ...]`（13 行）で落ちた
- 5 つの公開 API の spec の並べ替えと絞り込みの 11 examples は、引数を受け取るだけの仮の形で、並びと件数の期待の不一致で落ちた（在庫移動履歴の example は、最初に作った準備が CHECK 制約に当たったので、準備を直してから流し直した）

ほかの example は実装の後に書いたので、次の壊して落ちる記録で RED に代える。実装を 1 か所ずつ壊し、壊した箇所を確かめる spec のファイルだけを流し、複製から戻して更新時刻を進めた。`0fcd396` の上で壊し、実装レビューの直しの 3 つは `870aacb` の上で壊した。

| 壊したもの | 流した spec | 落ちた example |
|---|---|---|
| 件数の relation から scope と絞り込みを外す（`relation.unscope(:where).count`） | `graphql_matrix_spec.rb` | 96（うち RLS を開いた比較 91、絞り込みの変種の行が世界を絞る確かめ 5） |
| 並べ替えから id を外す | `page_spec.rb` | 3（ASC・DESC の境目と、計算した式の並べ替え） |
| 値のある行の後ろの条件から「値が空のもの」を外す | 同上 | 3 |
| 値が空の行の後ろの条件を、値のある行と同じ形にする | 同上 | 2 |
| `nulls_last` を外す | 同上 | 2（DESC だけ。PostgreSQL の ASC の既定は NULLS LAST） |
| カーソルから向きを外す | 同上 | 1（向きだけを変えたカーソルを拒む） |
| カーソルの整数の範囲を確かめない | 同上 | 1 |
| カーソルの日付の範囲を確かめない | 同上 | 1 |
| カーソルの文字列の文字コードを確かめない | 同上 | 1 |
| テナントの外で読んでも例外にしない | 同上 | 1 |
| 一度読んだ値をテナントを確かめずに返す | 同上 | 1 |
| `Page::Sort.of` が表に無い列を拒まない | 同上 | 1 |
| `totalCount` だけの問い合わせでページを読む | `query_budget_spec.rb` | 7（視点の直下の一覧の、件数だけの問い合わせの SQL の件数） |
| 在庫の一覧の `belowSafetyStock` を別の SQL で書き、不等号を `<=` にする | `stocks_spec.rb` | 1（ダッシュボードと一覧の件数を同じ世界で比べる） |
| 移動の種類の空の配列を絞らない扱いにする | 同上 | 1 |
| `keyword` の `%` をエスケープしない | `catalog_spec.rb`（packs） | 1 |
| `keyword` の前後の空白を除かない | 同上 | 1 |
| `keyword` の上限を 101 にする／99 にする | `spec/requests/catalog_spec.rb` | どちらも 1（100 文字と 101 文字の example） |
| 受注の得意先の絞り込みを外す | `sales_orders_spec.rb`・`tenant_boundary_spec.rb`・`graphql_matrix_spec.rb` | 2（公開 API の spec と S1。行列は受注日でも絞るので落ちない） |
| 受注日の終わりを含めない | `sales_orders_spec.rb` | 1 |
| 発注の受注側の絞り込みを外す | `purchase_orders_spec.rb`・`tenant_boundary_spec.rb`・`graphql_matrix_spec.rb` | 2（公開 API の spec と S1） |
| 発注日の始まりを含めない | `purchase_orders_spec.rb` | 1 |
| 受注の一覧の scope を外す | `graphql_matrix_spec.rb` | 10（RLS を開いた比較） |
| 品目の一覧の絞り込みを外す | 同上 | 1（絞り込みの変種の行が世界を絞る確かめ） |
| `supplier.item` の scope を外す | 同上 | 4（RLS を開いた比較） |
| `viewer.tenant` が別のテナントを返す | `graphql_entry_spec.rb` | 1 |

テストの基盤として足したものは、行列の「絞り込みの変種の行が世界の行を絞る」確かめと `MatrixWorld#add_filter_rows`、予算の spec の `total_count_only`、S1 の表の `own` である。絞り込みを外すと前者が落ち（上の表）、`own` の確かめは自社の ID で行が返らなければ落ちる。

### 確かめたこと

`dc2a367` で、Ruby 3.4.11 で M39 の完了条件と共通の完了条件を流した。この worktree では `bin/ci` の Setup の工程が落ちる（IB-72）ので、`config/ci.rb` の Setup のほかの工程を同じコマンドで 1 つずつ流した。

```sh
bundle exec rspec <完了条件の 1 つ目のコマンド>      # 47 examples, 0 failures
bundle exec rspec <完了条件の 2 つ目のコマンド>      # 1512 examples, 0 failures
bin/check-schema-compat                              # 落とす変更なし（足したのは省いてよい引数・フィールド・型だけ）
COVERAGE=1 bundle exec rspec                         # 2752 examples, 0 failures（2 分 9 秒）
BASE_REF=origin/main bin/check-branch-coverage       # 一覧は空
bin/check-open-items --due M39                       # 終了コード 0
bundle exec rspec --tag concurrency                  # 2 回続けて 61 examples, 0 failures
```

rubocop・packwerk・brakeman・bundler-audit・`bin/check-structure`・`bin/check-alerts`・`bin/check-commit-refs` も通った。分岐の網羅率の警告は 0 件で、example を足した件数も 0 件である。

行列の spec の時間（手元、`bundle exec rspec <ファイル>` を 2 回ずつ、`dc2a367`）は、`graphql_matrix_spec.rb` が 577 examples で 9.11 秒・9.40 秒、`table_matrix_spec.rb` が 804 examples で 7.46 秒・7.36 秒である。M38 の記録（491 examples、7.99 秒・7.37 秒）より入口の行列が 86 examples と約 1.5 秒増えた。2 ファイルを合わせて約 17 秒で、IB-50 の調べ直す条件（合わせて 30 秒を超える）には当たらない。

### 残件の処理

引当先が M39 の行は、着手の前と PR の前に台帳を読み、OI-12 だけだった。`supplier.item(id:)` と `viewer.tenant` を足して閉じた（`8f63a4d`）。OI-07・OI-78 の作者の判断（サーバーで並べ替えと絞り込み、件数）はこの PR で反映し、OI-144（並べ替えの列を一覧の表の列に限る）は既定のまま進めた（引当先は M33）。実装で決めたことは OI-153〜OI-157 に judgment で積み、違和感は IB-73〜IB-78 に積んだ。件数とページを同じ relation から引く形は、`Page.of` が relation を 1 つだけ受け取ることで守っており、IB-68 の候補と関わる。

## M40 状況での絞り込み

`m40-status-filter`（base は `main`）の PR。PR #55（`cycle-05-plan`）・#56（`m38-update-policy`）・#57（`m39-list-ordering`）が未マージなので、その commit も差分に見える。M40 の差分は `48dd2a1..` である。

Codex も Claude も Go で、Critical・High は無かった。どちらの系統も、`48dd2a1..557d7ee` の diff を `557d7ee` の版で読んだ。Codex は read-only のサンドボックスでテストを流さず、依頼に書いた実行結果を前提にし、DB の要らない確かめ（Arel が組む SQL と、世界の行を作る処理をメモリの上で流したもの）だけを流した。Claude は展開したコピーで rspec を流そうとしたが実行の許可が下りず、依頼と証跡の実行結果を前提にした。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Critical・High が無かったので、読み直しは回していない。指摘は `ea1e224`（コード）と `7e289fb`（文書）で直した。

| 系統 | 判定 |
|---|---|
| Codex | Go |
| Claude | Go |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R2） | 指摘なし |
| 正しさ | 指摘なし | 指摘（R3） |
| 境界と規約 | 指摘なし | 指摘（R1） |
| テストの検出力 | 指摘（R1） | 指摘なし |
| 参照の維持 | 指摘（R2・R3） | 指摘（R1・R2） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | R1：受注・発注の変種の行は受注日・発注日でも絞るので、世界の「列の絞り込みに当たり、状況で外れる行」を消しても、「変種の行が世界を絞る」確かめが通る | `graphql_matrix_spec.rb` に、状況でも絞る変種の行が、どのペルソナでも状況を外した件数より少なく絞ることを確かめる example を足した。世界の取消していない受注・発注を消すと落ち、3 つの一覧の状況の絞り込みを外しても落ちる（下の表）。出荷依頼は、出荷指示と出荷実績の表ごとの行が作る出荷依頼が状況で外れるので、世界に足した取消済の出荷依頼を消した。`testing.md`「行列テストとの分担」にこのガードを書いた | `ea1e224`・`7e289fb` |
| Low | Codex | R2：OI-159（出荷期限）と OI-160（子の行の所有テナント）が、計画の M40 の節に無い | 作るもの 3 とテナントの境界の段落に書いた | `7e289fb` |
| Low | Claude・Codex | Claude R2・Codex R3：状況の空の配列が 0 件になるのは Arel の `In` の振る舞いによるのに、根拠を引いていない。`Case`・`TableAlias`・`NamedFunction` の振る舞いも引いていない。`Page.of` が行の列を relation と別に受け取る理由がコメントに無い | 3 つの `filtered` に `Arel::Visitors::ToSql#visit_Arel_Nodes_In` を、`Page.of` に、`select` を掛けた relation の `count` が SQL のエラーになることを書いた。エラーは使い捨ての spec で `PG::SyntaxError` になることを確かめた。`adr/010` の確認した事項に、依存する Arel の振る舞いと activerecord 8.1.4 の原文の場所を書いた | `ea1e224`・`7e289fb` |
| Low | Claude | R1：式が読む子の表の列挙（外部キーで親と同じテナントに限られる表）に検収が無い。受注と発注の式に、子の行の守り方のコメントが無い | `adr/010`・`data-model.md`・`testing.md`・計画・OI-160 の列挙に検収を足し、2 つの式にコメントを足した。直す前の列挙は、`git grep` で残っていないことを確かめた | `ea1e224`・`7e289fb` |
| Low | Claude | R3：品番照合待ちの `EXISTS` が、読まない引当の副問い合わせを結ぶ。式を足した一覧の SQL の時間を、共有のデータの件数で測っていない | 品番照合待ちは引当を結ばない明細の `EXISTS` にした。共有のデータで測ることは IB-79 に積んだ | `ea1e224` |

違和感は次のように扱った。

- Claude 1：`SqlSubquery` の役割の名前が在庫の列の名前と同じ綴りで、受注のパッケージが在庫の列を書いているのと見分けがつかない → 役割の名前を `line_id`・`allocated_quantity` にした（`ea1e224`）
- Claude 2：`SqlSubquery` を scope を掛けた公開 API の戻り値だけに限る仕組みが無い → IB-80
- Claude 3：取消の可否で、状況を読む受注に scope を掛けていない → IB-81
- Claude 4：出荷済が出荷実績の有無だけで決まり、出荷指示と非対称になりうる → IB-82
- Codex 1：明細の無い受注が引当済になることを、spec に書いていない → IB-83

### 実装の記録

#### 計画との違い

計画に書かれていないことを決めたものは、OI-158〜OI-160 に judgment で積んだ。入口の行列の出荷依頼の変種の行を `#orderBy` から `#filter` に変え、並べ替えと状況を渡す（OI-158）。ダッシュボードの出荷期限の「出荷も取消もしていない」を、状況の式の絞り込みで書き直す（OI-159）。状況の式が子の行を読む副問い合わせに policy の scope を掛けず、外部キーの無い出荷停止だけ所有テナントを出荷依頼にそろえる（OI-160、`adr/010` 決定 3）。

ほかに、次の 3 つを計画の書き方から変えた。どれも作るものの意味は変えていない。

- 計画の壊して落ちる記録は、優先順の入れ替えを「取消済みで出荷済みの受注」で確かめると書くが、受注の取消済と出荷済、発注の受注側による取消と取消済は、DB の CHECK 制約（`sales_orders_cancelled_or_shipped`・`purchase_orders_single_cancellation`）で同時に持てない。計画の例を「検収済で出荷済の受注」に直し、作れない組は組まないと書いた（`1f44023`）。受注の品番照合待ちの行は、照合前の明細にも全量の引当を作り、引当済の条件にも当たる形にした。実際の引当は照合の後にしかできないが、優先順を確かめるには両方に当たる行が要る
- `Page.of` に、行と一緒に読む式（`columns:`）を足した。状況の式を行の `SELECT` に載せ、件数の `COUNT(*)` には入れない。公開 API が `select` を掛けた relation を渡すと、件数の SQL が複数の列を数えようとして失敗するからである
- 受注の状況の式は、`Sales::SalesOrderStatus.expression(actor)` が在庫の公開 API から副問い合わせを受け取って作る。一覧・1 件・件数・取消の可否の 4 か所が同じ呼び方で式を得る

Brakeman は副問い合わせを結ぶ箇所に警告を出さなかったので、`config/brakeman.ignore` は足していない。副問い合わせの文字列は `SqlSubquery#as` が `Arel.sql` で包み、Arel のノードとして結ぶ。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：

- 3 つの状況の spec（導出表の行ごとに 1 件ずつ作り、`statuses` で絞る形に書き直したもの）は、公開 API が `statuses` を受け取るだけで無視する仮の形で、9 examples のうち 8 が落ちた。`got:` には、絞られずに全行が返った（受注の導出表の example は、取消済で絞って 7 件が返った）。落ちなかった 1 つ（取り消した出荷指示と解除した出荷停止を数えない）は、絞る状況が全行を覆っていたので、下の壊して落ちる記録で RED に代える。最初に書いた準備は CHECK 制約に当たったので、準備を直してから流し直した

ほかの example は実装の後に書いたので、次の壊して落ちる記録で RED に代える。実装を 1 か所ずつ壊し、壊した箇所を確かめる spec のファイルだけを流し、複製から戻して更新時刻を進めた。`c38eea2` の上で壊し、`allocation_spec.rb` の対照を直した後の副問い合わせの scope は `ae7adbb` の上で壊し直した。

| 壊したもの | 流した spec | 落ちた example |
|---|---|---|
| 受注の式の検収済と出荷済を入れ替える | `sales_order_status_spec.rb` | 1（導出表の行ごと） |
| 受注の式の品番照合待ちと引当済を入れ替える | 同上 | 1 |
| 受注の式の出荷済と品番照合待ちを入れ替える | 同上 | 1 |
| 受注の式の引当済と一部引当を入れ替える | 同上 | 2（導出表の行ごと、解除した引当） |
| 一部引当の条件を「引当数量 > 1」にする | 同上 | 1 |
| 引当済の条件を「引当数量 ≦ 明細の数量の明細が無い」にする | 同上 | 2 |
| 引当の副問い合わせを内部結合にする | 同上 | 3（引当の無い明細が消える） |
| 発注の式の検収済と入荷予定を入れ替える | `purchase_order_status_spec.rb` | 1 |
| 発注の式の受注済と受注側で確認中を入れ替える | 同上 | 1 |
| 出荷依頼の式の出荷済と出荷停止中を入れ替える | `shipment_request_status_spec.rb` | 1 |
| 出荷依頼の式の出荷停止中と出荷指示済を入れ替える | 同上 | 1 |
| 取り消した出荷指示も数える（`active` の scope を外す） | 同上 | 1（取り消した出荷指示と解除した出荷停止） |
| 解除した出荷停止も数える | 同上 | 1（同上） |
| 出荷停止を受注で結ばない | 同上 | 3 |
| 出荷停止の所有テナントを出荷依頼にそろえない | 同上と `spec/matrix` | 1（RLS を開いた example。行列は落ちない） |
| 引当の副問い合わせから解除済みを除く条件を外す（`quantities_for` と共通） | `sales_order_status_spec.rb`・`allocation_spec.rb` | 3（解除した引当、`quantities_for` の解除、副問い合わせ） |
| 引当の副問い合わせから scope を外す | `allocation_spec.rb`・`spec/matrix` | 1（RLS を開いた example。行列は落ちない） |
| `count_by_status` を取消済を除いて数える | `sales_orders_spec.rb`・`dashboard_spec.rb` | 4（件数と絞った一覧の比較、状況ごとの件数 2、ダッシュボード） |
| 受注・発注・出荷依頼の `statuses` の空の配列を絞らない扱いにする | 3 つの状況の spec | どれも 1 |
| 受注の `statuses` の絞り込みを外す | `sales_order_status_spec.rb`・`spec/matrix` | 3（行列は受注日でも絞るので落ちない） |
| 発注の `statuses` の絞り込みを外す | `purchase_order_status_spec.rb`・`spec/matrix` | 2（同上） |
| 出荷依頼の `statuses` の絞り込みを外す | `shipment_request_status_spec.rb`・`spec/matrix` | 4（うち行列の「変種の行が世界を絞る」確かめ 1） |
| 出荷期限から出荷停止中を外す | `shipment_requests_spec.rb` | 1 |
| 取消の可否で状況を記号と比べる（常に偽） | `packs/sales/spec` | 2（`order_cancellation_spec.rb`・`cancellation_reviews_spec.rb` の出荷可能を出した受注の取消） |

実装レビューの直しの後は、`ea1e224` の上で次を壊した。

| 壊したもの | 流した spec | 落ちた example |
|---|---|---|
| 世界の取消していない受注・発注を消す | `graphql_matrix_spec.rb` | 1（状況でも絞る変種の行のガード） |
| 受注の `statuses` の絞り込みを外す | 同上 | 1（同上） |
| 発注の `statuses` の絞り込みを外す | 同上 | 1（同上） |
| 出荷依頼の `statuses` の絞り込みを外す | 同上 | 2（同上と、変種の行が世界を絞る確かめ） |
| 受注の式の品番照合待ちと引当済を入れ替える | `sales_order_status_spec.rb` | 1 |
| 品番照合待ちの条件を「品目のある明細がある」にする | 同上 | 3 |

2 つの守りが同じ条件を持つのは、副問い合わせの scope と RLS、出荷停止の所有テナントのそろえと RLS である。どちらも RLS を開かない限り他社の行が見えないので、式の側を壊したときは RLS を開いた単体だけが落ち、行列は落ちない。RLS の側を壊すのは表の行列（`table_matrix_spec.rb`）が確かめる。

テストの基盤として足したものは、`MatrixWorld#add_filter_rows` の取消済と取消していない受注・発注と、行列の「状況でも絞る変種の行が、状況を外した件数より少なく絞る」ガードである。ガードは実装レビューの直しで足した（Codex R1）。それまでは、受注と発注は受注日・発注日でも絞るので、状況の絞り込みを外しても行列は落ちず、状況の spec だけが落とした。いまは、取消していない行を消しても、3 つの一覧の状況の絞り込みを外しても、ガードが落ちる（上の 2 つ目の表）。ガードは、状況でも絞る行が受注・発注・出荷依頼の 3 つであることを先に確かめ、対象の無いまま通らないようにした。

### 確かめたこと

実装レビューの直しの後の `7e289fb` で、Ruby 3.4.11 で M40 の完了条件と共通の完了条件を流した。この worktree では `bin/ci` の Setup の工程が落ちる（IB-72）ので、`config/ci.rb` の Setup のほかの工程を同じコマンドで 1 つずつ流した。

```sh
bundle exec rspec <完了条件の 1 つ目のコマンド>      # 10 examples, 0 failures
bundle exec rspec <完了条件の 2 つ目のコマンド>      # 30 examples, 0 failures
bundle exec rspec <完了条件の 3 つ目のコマンド>      # 1446 examples, 0 failures
bin/check-schema-compat                              # 落とす変更なし（足したのは省いてよい引数と型だけ）
COVERAGE=1 bundle exec rspec                         # 2747 examples, 0 failures（2 分 17 秒）
BASE_REF=origin/main bin/check-branch-coverage       # 一覧は空
bin/check-open-items --due M40                       # 終了コード 0
bundle exec rspec --tag concurrency                  # 2 回続けて 61 examples, 0 failures
```

rubocop・packwerk・brakeman・bundler-audit・`bin/check-structure`・`bin/check-alerts`・`bin/check-commit-refs`・`bin/test-layers` も通った。分岐の網羅率の警告は 0 件で、example を足した件数も 0 件である。

行列の spec の時間（手元、`bundle exec rspec <ファイル>` を 2 回ずつ、`7e289fb`）は、`graphql_matrix_spec.rb` が 579 examples で 9.55 秒・9.58 秒、`table_matrix_spec.rb` が 804 examples で 7.43 秒・7.26 秒である。M39 の記録（577 examples、9.11 秒・9.40 秒）より入口の行列が 2 examples と約 0.3 秒増えた。2 ファイルを合わせて約 17 秒で、IB-50 の調べ直す条件（合わせて 30 秒を超える）には当たらない。

### 残件の処理

引当先が M40 の行は、着手の前と PR の前に台帳を読み、無かった。OI-07 の作者の判断（サーバーで並べ替えと絞り込み、件数）の残り（状況での絞り込み）をこの PR で反映した。OI-144（並べ替えの列を一覧の表の列に限る）は、状況での並べ替えを足さず既定のまま進めた（引当先は M33）。実装で決めたことは OI-158〜OI-160 に judgment で積み、違和感と測っていない性能は IB-79〜IB-83 に積んだ。

## M33 フロントエンド

`m33-frontend`（base は `main`、PR #59）。PR #55〜#58 が未マージなので、その commit も差分に見える。M33 の差分は `971e6dc..` である。流用元 factory-ops-demo の commit 958de71 の `frontend/` を写した（`6ca98dd`）。

Codex は Conditional Go、Claude は Go だった。どちらの系統も、`971e6dc..9c31e25` の diff を `9c31e25` の版で読み、テストは流さず、依頼に書いた実行結果を前提にした。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex の High は 2 件で、M33-R1 は `fe3cc7b` で直した。M33-R2（OI-144 と検収表の受け入れが作者を待つ）は実装者が直せないので、作者に渡す事項として残した。High があったので Codex に読み直しを 1 回出し、`fe3cc7b` の版で、M33-R1 は解消、M33-R2 は作者を待つため未解消、新しい High は無し、判定は Conditional Go のままだった（OI-144 の判断と検収表の受け入れが済めば Go）。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Conditional Go（High 2・Medium 4・Low 1） | Conditional Go（R1 解消、R2 は作者待ち、新しい High なし） |
| Claude | Go（Medium 2・Low 7） | 出していない（High が無かった） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R2） | 指摘（R1） |
| 正しさ | 指摘（R1・R3・R4） | 指摘（R7・R8） |
| 境界と規約 | 指摘なし | 指摘（R4） |
| テストの検出力 | 指摘（R5・R6） | 指摘（R2・R3・R9） |
| 参照の維持 | 指摘（R7） | 指摘（R5・R6） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex | R1：取り込みのファイルの送り先を決める `next.config.mjs` の `rewrites` はビルドの時の値で固まり、E2E では Rails の 3200 ではなく 3000 へ送る | route handler（`app/imports/files/route.ts`）が実行の時の `RAILS_URL` へ送る形にした（OI-167）。取り込みの E2E を足し、`rewrites` に戻すと落ちた | `fe3cc7b` |
| High | Codex | R2：OI-144 が blocked-user のままで `--due M33` が落ち、検収表の受け入れが無い | 作者の判断と受け入れを待つ。PR と下の「残件の処理」に書いた | — |
| Medium | Codex・Claude | Codex R5・Claude R1：ログインの画面が寸法の測りと検収表に入らない。流用元の色の検査を画面に繋いでいない | 画面の収集を `app/` の全部のルートのグループにし、ログインの画面をログインせずに測る。全画面をライトとダークで axe のコントラストで測る E2E を足し、`--muted-foreground` を薄くすると落ちた。操作中の状態は IB-88 | `fe3cc7b` |
| Medium | Claude | R2：呼び出し口・Cookie の写し・ユーザーエラーの分け方に、壊すと落ちるテストが無い | vitest で fetch と next の関数を差し替え、エラーの表の行ごとと Cookie の往復を確かめる 16 examples を足した。`writeSessionCookie` の復号・`sessionHeader` の符号化・NOT_PERMITTED の文言を壊すと、それぞれ落ちた | `fe3cc7b` |
| Medium | Codex | R3：品番の対応表の品目の候補が先頭 100 件に固定される | 候補をキーワードで 20 件ずつ引く形にし、予算の表の行を合わせた | `fe3cc7b` |
| Medium | Codex | R4：検収と取消依頼の入力の誤りを、入力欄の下に出さない | `lines.<i>.acceptedQuantity` と `reason` を入力欄の下に出す | `fe3cc7b` |
| Medium | Codex | R6：rake タスクがワーカーの守りを呼ぶことを確かめていない | 心拍の生きているワーカーを登録して `e2e:check` と `e2e:prepare` を流す example を足した。どちらの呼び出しを外しても落ちた | `fe3cc7b` |
| Low | Claude | R3：admin に限るボタンを member で確かめていない | 5 つの画面を admin で開いて出ること（対照）と、member で出ないことを確かめる E2E を足した。受注の取消のボタンの `admin &&` を外すと落ちた | `fe3cc7b` |
| Low | Claude | R4：ESLint が fetch の `cache: "force-cache"` を止めない | `cache` が `no-store` 以外なら落とす規則を足した | `fe3cc7b` |
| Low | Claude | R5：Next の Cookie と Rails の db:prepare と Playwright の止め方の根拠を引いていない | next 16.4.0 の `stringifyCookie`・`parseCookie`・`MutableRequestCookiesAdapter.wrap` と、Playwright 1.64 の `gracefulShutdown` の説明を引いた | `fe3cc7b` |
| Low | Claude | R6：計画の fragment の規則が graphql-schema.md と食い違う | 計画を「fragment は使わない」にした | `fe3cc7b` |
| Low | Claude | R7：Int の範囲を超える入力が、欄の誤りでなくトップレベルのエラーになる | −2^31〜2^31−1 を入力欄で確かめる（上限ちょうどと上限 + 1 の単体を足した） | `fe3cc7b` |
| Low | Claude | R8：取り込みのファイルの送信の 401 で、Cookie を消してログインへ移さない | セッションの切れた先（`/session/expired`）へ移す | `fe3cc7b` |
| Low | Claude | R9：失効の後のカタログと、かんばんのカードの確かめが、別の理由の表示でも通る | カタログの「見られません」の文言で確かめ、ダッシュボードにカードがあることを先に確かめる | `fe3cc7b` |
| Low | Codex | R7：graphql-schema.md のセッションの期限が、画面では延びないことを書いていない | 「1 回のリクエストがたどる道」1 に書いた | `fe3cc7b` |

違和感は次のように扱った。

- Claude 1：M33 を閉じる時点は OI-144 と検収表の受け入れで決まる → PR と「残件の処理」に書いた
- Claude 2：寸法と検収表は admin の画面だけを測る → IB-84
- Claude 3：発注詳細の受注側の出荷と取消依頼を予算で計らない → IB-85
- Claude 4：表の部品のコメントの例に、外した得意先の住所と担当者が残る → 消した（`fe3cc7b`）
- Claude 5：`e2e:check` が `StatementInvalid` を丸ごと握る → 表が無いときだけ握る形にした（`fe3cc7b`）
- Claude 6：`playwright.config.ts` の「止まる」が、待つとも失敗するとも読める → しきい値を過ぎるまで失敗すると書いた（`fe3cc7b`）
- Claude 7：`/session/expired` を GET で開くと Cookie が消える → IB-87
- Codex 1：業務の今日だけを読む画面も、ダッシュボードの入口を通る → IB-86
- Codex（読み直し）：取り込みのファイルの本文を route handler が全量読んでから送る → IB-89

### 実装の記録

#### 計画との違い

計画に書かれていないことを決めたものは、OI-161〜OI-167 に judgment で積んだ。予算の表の一覧を持たない文書と詳細の親（OI-161）、取引用コードの `NOT_FOUND` を入力欄に出すこと（OI-162）、Node 22 と依存の版（OI-163）、ダッシュボードの KPI（OI-164）、一覧のタブのまとまり（OI-165）、キャッシュを使わない理由（OI-166）、取り込みのファイルを route handler で送ること（OI-167）である。

ほかに、次を計画の書き方から変えた。

- E2E の準備（OI-143）：計画は `bin/rails e2e:prepare` の 1 つのタスクが DB を作り直すと書いていた。`DemoWorld` を読み込んだプロセスの中で `db:drop`・`db:prepare` を呼ぶと、作り直した DB に構造を読み込まずに終わったので、`e2e:check`・`db:drop db:prepare`・`e2e:prepare` を別のコマンドに分け、`frontend/e2e/start-rails.sh` がこの順に流してから `bin/jobs` を起こす。計画の作るもの 4 を直した
- ダッシュボードの出荷期限の件数は、出荷依頼の一覧が期限で絞れないので、同じ条件の行を並べた同じ画面の表へ飛ぶ（OI-164、`c41295b`）

画面の部品のうち、受注の明細ごとの引当とカードからの一括の引当（流用元の `bulk-allocation`）は、`allocateSalesOrder` が受注の単位で引き当てるので写さなかった。全件を読んで画面で並べる純関数（`sortRows`・`buildOrderList`・`sample` の絞り込み）は、URL の値を変数に写す関数（`lib/list.ts`・`lib/*-list.ts`）に替えた。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：

- `spec/graphql/query_budget_spec.rb` の、画面の問い合わせのファイルの一覧が予算の表と一致する example は、読み先を `frontend/graphql/` に替えた時点で、表に無い query の文書（`BuyerOrderForm`・`ViewerShell` など）が `the extra elements were:` に並んで落ちた（`fde0d5b` の後、表に行を足す前）

ほかの spec と E2E は実装の後に書いたので、次の壊して落ちる記録で RED に代える。実装を 1 か所ずつ壊し、壊した箇所を確かめる spec か E2E だけを流し、複製から戻した。E2E は壊すたびに `next build` をやり直した。

| 壊したもの | 流したもの | 落ちたもの |
|---|---|---|
| 1 ページの件数（`PAGE_SIZE`）を 100 にする | `e2e/list-pagination.spec.ts` | 2（1 ページ目の 20 件、2 ページ目の有無） |
| URL の `dir` を `orderBy` の向きに逆に写す | 同上 | 1（並べ替えの見出し） |
| 失効の後の NOT_PERMITTED を API の文言で出す | `e2e/revocation.spec.ts` | 1 |
| `request.ts` が最初に読んだセッションを使い続ける | `e2e/tenant-switch.spec.ts` | 1 |
| かんばんの受注済の列を引当済で絞る | `e2e/counts.spec.ts` | 1 |
| 請求の締めの取引先の選択欄を元の幅に戻す | `e2e/layout.spec.ts` | 1（`/supplier/billing` の 390px） |
| 測る画面の表から `/missing` の行を消す | 同上 | 収集の時点で落ちた |
| 接続の失敗をトップレベルのエラーに分ける | `e2e/unreachable.spec.ts` | 2 |
| 取り込みの送り先を `rewrites` に戻す | `e2e/imports.spec.ts` | 1 |
| 受注の取消のボタンの `admin &&` を外す | `e2e/admin-only.spec.ts` | 1 |
| `--muted-foreground` を薄くする | `e2e/contrast.spec.ts` | 複数の画面のコントラストの違反 |
| `writeSessionCookie` の復号を外す・`sessionHeader` の符号化を外す・NOT_PERMITTED を API の文言にする | `lib/graphql/*.test.ts` | それぞれ 1 以上 |
| 予算の表のかんばんの `page_size` を外す | `query_budget_spec.rb` | 4（1 件と 20 件の比較と、負例 3） |
| 件数だけの問い合わせで、名前で選んでほかの選択を残す | 同上 | 11（件数だけを選ぶ example 13 のうち） |
| `expect_lists` で上限を見ない | 同上 | 1（page_size のガード） |
| 登録の表から `StartImport` を消す | `metrics_subscriber_spec.rb` | 1 |
| `e2e:check`・`e2e:prepare` のワーカーの守りの呼び出しを外す | `spec/platform/e2e_prepare_spec.rb` | それぞれ 1 |
| 守りの関数の件数の比較と DB の名前の比較を外す | 同上 | それぞれ 1 |
| コメントの検査の台帳の ID の規則を外す | `scripts/check-comments.test.mjs` | 2 |

計画の「手で確かめる」4 つは次のとおりである。`schema.graphql` の `SalesOrder.orderNo` を消すと、`npm run codegen:check` が `Cannot query field "orderNo" on type "SalesOrder"` で落ちた。`request.ts` の先頭に `"use cache"` を足すと、`npm run lint` が `no-restricted-syntax` で落ちた。並べ替えの向きを取り違える確かめは上の表の 2 行目である。検収表の受け入れは作者を待つ（下の「残件の処理」）。

テストの基盤として足したものは、E2E の世界の準備（`e2e:check`・`e2e:prepare`・`start-rails.sh`）、ワーカーごとのアカウントの読み出し（`e2e/support/world.ts`）、画面の収集（`e2e/support/screens.ts`）である。準備の守りは上の表の 2 行（rake タスクの呼び出しと関数）で、画面の収集は `/missing` の行を消すと落ちることで確かめた。

### 確かめたこと

実装レビューの直しの後の `fe3cc7b` で、Ruby 3.4.11・Node 22.23.3 で流した。この worktree では `bin/ci` の Setup の工程が落ちる（IB-72）ので、`config/ci.rb` の Setup のほかの工程を同じコマンドで 1 つずつ流した。

```sh
cd frontend && npm run codegen:check && npm run lint && npm run typecheck && npm run test:unit   # 14 files, 136 tests
cd frontend && PLAYWRIGHT_CHANNEL=chrome npm run test:e2e   # 2 回続けて 65 passed・25 skipped（約 51 秒）
bundle exec rspec spec/graphql/query_budget_spec.rb spec/graphql/query_complexity_spec.rb spec/platform/metrics_subscriber_spec.rb   # 0 failures
COVERAGE=1 bundle exec rspec                         # 2810 examples, 0 failures
BASE_REF=origin/main bin/check-branch-coverage       # 一覧は空
bin/check-open-items --due M33                       # OI-144（blocked-user）で落ちる
```

rubocop・packwerk・`bin/check-open-items`・`bin/check-commit-refs`・`bin/check-schema-compat` も通った。分岐の網羅率の警告は 2 件（`lib/e2e_prepare.rb` のワーカーの数の分岐）で、2 件とも example を足した。rspec の全件を E2E と同時に流すと、`spec/platform/logging_spec.rb` の 1 つが落ちた。E2E の Rails も test の環境で `log/events.log` に書き、その spec がファイルの末尾を読むからである。単独で流し直して通り、`README.md`「画面」に同時に流さないことを書いた。PR #59 の CI は、`9c31e25` で全ジョブ（e2e 2 分 39 秒・frontend 40 秒・test 5 分 29 秒）が通った。

手元で `bin/rails server` と `next dev` を起こし、シードのアカウントでログインして、受注側（ダッシュボード・受注・在庫・品目・取引関係・請求の締め・請求書・取り込み・自社の情報・監査ログ）と発注側（取引先とカタログ・発注・発注登録・受領請求書）の画面を開いた。書き込みは、担当の画面ごとに引当・出荷指示とその取消・出荷実績・品目の登録と公開・単価の改定の予約・在庫の調整・品番の対応の登録・取引関係の結び直しと失効・締め日の設定・下書きの破棄と締め直し・取り込み・発注の登録・取消依頼を 1 回ずつ通した。

検収表のスクリーンショット（25 画面 × ライト・ダーク × 1280・1024・390px、150 枚）は `E2E_SCREENSHOTS=1` で撮れる。担当者は、ダッシュボード・発注詳細・在庫の 390px などを見比べてから作者に渡した。

### 残件の処理

引当先が M33 の行は、着手の前と PR の前に台帳を読んだ。OI-17・OI-142・OI-143 を閉じた。OI-06〜OI-14 は作者の判断どおりに作った（OI-07 の一覧の読み方、OI-08 の色、OI-09 のログインの画面、OI-10 のサイドバー、OI-11 の期限、OI-13 の入荷予定のタブ。OI-14 の配置は M41）。M33 で決めたことは OI-161〜OI-167 に judgment で積んだ。

作者を待つものは 2 つある。OI-144（並べ替えの列を一覧の表に限るか）は blocked-user のままで、既定（限る）で作った。並べ替えの見出しは orderBy の field から作るので、作者が変えれば、API に列を足すと見出しが足りないことを型検査が知らせる。もう 1 つは検収表のスクリーンショットの受け入れで、計画は作者が受け入れるまで M33 を終えないとする。作者は 2026-10-13 に検収表を受け入れた（作者の言葉は「画面は受け入れます。細かい指摘はあるのですが、実際に動かして他の箇所を見てから直します」）。これで M33 の完了条件のうち検収表の受け入れは満たした。細かい指摘は、作者が実際に動かした後に出すので、OI-177 に open で積み、M33 で直す。OI-138・OI-139・OI-141（E2E の世界の中身と、シードが監査の行を書かないこと）は judgment のまま作者の確認を待つ。

## M41 Raspberry Pi の k3s への配置

`m41-k3s-deploy`（base は `main`、PR #60）。PR #55〜#59 が未マージなので、その commit も差分に見える。M41 の差分は `488645a..` である（`488645a` は M33 のブランチの先端）。

Codex は Conditional Go、Claude は Go だった。どちらの系統も、`488645a..5dca71c` の diff を `5dca71c` の版で読み、テストは流さず、依頼に書いた実行結果を前提にした。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex の High は 3 件で、R2 と R3 は `844c291` で直した。R1（OI-145〜OI-149 が作者を待つことと、CI の `images` のジョブの結果）は実装者が直せない部分を含むので、作者に渡す事項と CI の結果として残した。High があったので Codex に読み直しを 1 回出し、`844c291` の版で、R2〜R6 は解消、R1 は作者待ちと CI の結果待ち、新しい High は無し、判定は Conditional Go のままだった（`844c291` の `images` のジョブが通れば Go）。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Conditional Go（High 3・Medium 3） | Conditional Go（R2〜R6 解消、R1 は作者待ちと CI の結果待ち、新しい High なし） |
| Claude | Go（Medium 3・Low 4） | 出していない（High が無かった） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R1） | 指摘（R4） |
| 正しさ | 指摘（R3・R6） | 指摘（R1・R5・R6） |
| 境界と規約 | 指摘（R2） | 指摘（R3） |
| テストの検出力 | 指摘（R4・R5） | 指摘（R2・R3） |
| 参照の維持 | 指摘なし | 指摘（R7） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High | Codex | R1：OI-145〜OI-149 が blocked-user で `--due M41` が落ち、CI の `images` のジョブが未実行 | `--due M41` は作者の判断を待つ。下の「残件の処理」に書いた。`images` のジョブの結果は「確かめたこと」に書いた | — |
| High | Codex・Claude | Codex R2・Claude R6：パスワード・暗号化鍵・PAT が `kubectl` と `psql` の引数に入る | 手順書の Secret の作り方を、ヒアドキュメントと標準入力で `kubectl create -f -` に渡す形にし、PAT は手元で読んで組み込みの `printf` で組み立てて ssh の標準入力で渡す。PostgreSQL の初期化は `\getenv` で環境変数から読む。手元の postgres:18.6 で、引用符と空白を含むパスワードでロールを作れた | `844c291` |
| High | Codex | R3：手で作った作り直しの Job と定時の Job が重なり、`DemoReset` に排他が無い | 所有ロールで保守用の DB（`postgres`）に接続してアドバイザリロックを取り、取れなければ何も触らずに止まる（OI-174） | `844c291` |
| Medium | Claude | R1：追い出された Pod が `Failed` のまま一覧に残り、毎日の作り直しが毎回 5 分待って失敗する | phase が `Succeeded`・`Failed` の Pod を待たない（OI-175） | `844c291` |
| Medium | Claude | R2：`SHARED_DEMO_ACCOUNTS` から設定への写しを確かめる spec が無い | `production_boot_spec.rb` で、未設定・`1`・`true` を子のプロセスで確かめる | `844c291` |
| Medium | Codex | R4：Role と Pod のラベルの期待値を、実装の定数（`DemoReset::DEPLOYMENTS`）から作る | spec に `RESET_TARGETS = %w[web jobs]` を独立に持ち、定数・セレクタ・Role をそれぞれ比べる | `844c291` |
| Medium | Codex | R5：`spec/support/env_helpers.rb` の戻しを確かめる example が無い | `spec/platform/env_helpers_spec.rb` を足した | `844c291` |
| Medium | Codex | R6：SIGTERM の後の猶予（30 秒）の間に、API の時間切れ（30 秒）の 2 つの要求が終わらない | 作り直しの Pod の猶予を 90 秒、API の時間切れを接続 5 秒・応答 10 秒にし、猶予が 2 つの和より長いことを spec で確かめる（OI-176） | `844c291` |
| Medium | Claude | R4：CI の `images` のジョブが通ったことを確かめていない | Codex R1 と同じ。「確かめたこと」に書いた | — |
| Low | Claude | R3：所有ロールのパスワードを持つコンテナを、変数の名前でしか数えない | `owner-password` のキーを読むワークロードが postgres・migrate・daily-reset だけで、`envFrom` が無いことを確かめ、手順書の Secret の表の「使うコンテナ」の列もマニフェストと比べる | `844c291` |
| Low | Claude | R5：手順書の migrate の失敗と、Pod が動く前の `logs -f` で詰まる | migrate が `Failed` で止まったときの見方と流し直し方、`logs` の前に Pod を待つことを書いた | `844c291` |
| Low | Claude | R7：計画の「接続をプールに返して」が `clear_all_connections!` の振る舞いと違う | 計画を「接続を切ってから（各プールの `disconnect!`）」に直した | `844c291` |

違和感は次のように扱った。

- Claude 1：DB のタスクの途中で SIGTERM を受けると、作りかけの DB に向けて web と jobs が起きる → `deploy/README.md`「作り直しが途中で止まったとき」に、手で流し直すことを書いた（`844c291`）
- Claude 2：本番の環境の外では、`demo:reset` の入口を `ServiceAccount` の場所が無いことで止めている → IB-90
- Claude 3：`images` のジョブはテストのジョブを待たずに push する。kubeconform の取得を確かめていない → push は IB-91。kubeconform は sha256 で確かめるようにした（`844c291`）
- Claude 4：postgres と web の Service に、同じ k3s のほかの名前空間から届く → IB-92
- Claude 5：`README.md` の文書の表で、`deploy/README.md` の行が ADR の並びを割る → 手順書の並びに移した（`844c291`）
- Claude 6：作り直しの最中に適用すると、web と jobs が途中で起きる → 手順書の「作者の手順」2 に、作り直しの時刻を避けることを書いた（`844c291`）
- Claude 7：spec の 2 つの `it` の間に空行が無い → 直した（`844c291`）
- Codex（読み直し）：SIGTERM の spec は `SignalException` を直接上げるだけで、子のプロセスを待つ間の振る舞いを確かめない → 本番のイメージで、子のプロセス（`sleep 60`）を待つ間に `docker stop`（SIGTERM）を送り、1 秒以内に web と jobs を 1 に戻して終わることを手で確かめた（下の「確かめたこと」）

### 実装の記録

#### 計画との違い

計画に書かれていないことを決めたものと、計画の書き方から変えたものは、OI-168〜OI-176 に judgment で積んだ。DB のタスクを子のプロセスで流し、`DISABLE_DATABASE_ENVIRONMENT_CHECK` を子のプロセスにだけ渡すこと（OI-168）、画面のイメージの standalone の選び方と文脈（OI-169）、Secret の名前とキー（OI-170）、公開のホスト名を Kustomize の 1 つの値から写すこと（OI-171）、`Recreate` と probe と ServiceAccount のトークンと Role の `resourceNames`（OI-172）、節の参照の spec をパスで引くこと（OI-173）、作り直しのアドバイザリロック（OI-174）、終わった Pod を待たないこと（OI-175）、終了の猶予と API の時間切れ（OI-176）である。計画の M41 の節と `adr/009`「確認した事項」を直した。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：

- `spec/requests/sessions_spec.rb`：共有のデモのアカウントの配置で、ほかのセッションが続く example が `expected: 200 got: 401` で落ちた（9 examples, 1 failure）
- `spec/platform/production_boot_spec.rb`：4 examples, 4 failures。Set-Cookie が空、production の設定に `host`・`port` が無い、`file_system` を渡しても `sendgrid`、`fake` で起動した
- `spec/platform/logging_spec.rb`：本番のミドルウェアの並びの example が、先頭の `ActionDispatch::AssumeSSL` の分だけ食い違って落ちた
- `spec/platform/deploy_manifests_spec.rb`：空の `deploy/` で 16 examples, 15 failures。期待の不一致で落ちたのは、置くものの種類と名前（`expected ["frontend", "jobs", "postgres", "web"] got []`）と、コンテナの資源（`got []`）の 2 つで、ほかはファイルが無いことと `nil` で落ちた
- 3 つの公開 API の spec（`onboarding_spec.rb`・`stocks_spec.rb`・`demo_world_spec.rb`）：`DEMO_WORLD_ENABLED=1` でも動く example が、`ProductionEnvironment` の例外で落ちた（33 examples, 3 failures）

実装の後に書いた spec と、上の RED のほかの条件は、次の壊して落ちる記録で RED に代える。実装を 1 か所ずつ壊し、壊した箇所を確かめる spec だけを流し、複製から戻した。

| 壊したもの | 流したもの | 落ちたもの |
|---|---|---|
| ログアウトの共有のアカウントの条件を外す・常に世代を進めない | `sessions_spec.rb` | それぞれ 1（共有のアカウントの example、世代を進める example） |
| `DemoWorldGate.open?` を常に真にする・`== "1"` を `present?` にする | 3 つの公開 API の spec | それぞれ 3（無いときと `true` のときの example） |
| `set_safety_stock` が門を読まずに `Rails.env.production?` で止める | 同上 | 2（`stocks_spec.rb` と、`DemoWorld.build` を最後まで流す example） |
| `assume_ssl` を偽にする | `production_boot_spec.rb`・`logging_spec.rb` | 2 |
| `NOTIFICATIONS_PROVIDER` の値の確かめを外す・owner の `host` を外す・`SHARED_DEMO_ACCOUNTS` を `present?` で読む | `production_boot_spec.rb` | それぞれ 1 |
| `demo:reset` の入口の門を外す | `demo_reset_spec.rb` | 1（入口の example） |
| `ensure` を外す・`rescue StandardError` にする | 同上 | 3（例外・Pod の待ちの上限・0 にする途中の失敗）、1（SIGTERM） |
| Pod の待ちを外す・phase を見ない | 同上 | 2（順と待ちの上限）、1（追い出された Pod） |
| `DISABLE_DATABASE_ENVIRONMENT_CHECK` を自分のプロセスに立てる・子に渡さない | 同上 | それぞれ 1 |
| ロックを見ない・owner の設定が無いときに止まらない | 同上 | それぞれ 1 |
| API の応答の時間切れを 60 秒にする・戻しで `Failed` しか拾わない | 同上 | それぞれ 1 |
| 作り直しが戻せなかったことをログに書かない | 同上 | 1 |
| rake タスクから `DemoReset.run` の呼び出しを外す | 同上 | 1 |
| web に `DEMO_WORLD_ENABLED` を足す・jobs のプールを 15 にする・Role に `delete` を足す・PVC を `/var/lib/postgresql/data` に付ける・タグを `latest` にする・daily-reset の `backoffLimit` を 2 にする・web を `NodePort` にする | `deploy_manifests_spec.rb` | それぞれ 1 |
| 手順書の Secret の表の行を消す・使う列を変える・web に別の名前で `owner-password` を渡す | 同上 | 1・1・2 |
| 作り直しの対象に frontend を足す・終了の猶予を 30 秒にする | 同上 | それぞれ 1 |
| 節の参照の spec で、パスの全体が一致する文書の優先を外す | `section_references_spec.rb` | 1 |
| 環境変数の補助の戻しを外す | `env_helpers_spec.rb` | 2 |

テストの基盤として足したものは、環境変数の補助（`spec/support/env_helpers.rb`）で、戻しを外すと `env_helpers_spec.rb` の 2 つが落ちる。`deploy/preflight.sh --list` の出力は `deploy_manifests_spec.rb` がマニフェストから集めた一覧と比べる。

### 確かめたこと

`844c291` で、Ruby 3.4.11・Node 22.23.3 で流した。この worktree では `bin/ci` の Setup の工程が落ちる（IB-72）ので、`config/ci.rb` の Setup のほかの工程を同じコマンドで 1 つずつ流した。

```sh
bundle exec rspec spec/platform/deploy_manifests_spec.rb spec/platform/demo_reset_spec.rb spec/platform/production_boot_spec.rb spec/platform/logging_spec.rb spec/scenarios/demo_world_spec.rb packs/partnerships/spec/public/partnerships/onboarding_spec.rb packs/inventory/spec/public/inventory/stocks_spec.rb spec/requests/sessions_spec.rb   # 0 failures
COVERAGE=1 bundle exec rspec                         # 2855 examples, 0 failures
BASE_REF=origin/main bin/check-branch-coverage       # 一覧は空
bin/check-open-items --due M41                       # OI-145〜OI-149（blocked-user）で落ちる
cd frontend && npm run codegen:check && npm run lint && npm run typecheck && npm run test:unit   # 136 passed
cd frontend && PLAYWRIGHT_CHANNEL=chrome npm run test:e2e   # 65 passed・25 skipped
kubectl kustomize deploy                             # 公開のホスト名が Ingress と FRONTEND_ORIGIN に入る
```

rubocop・packwerk・brakeman・bundler-audit・`bin/check-structure`・`bin/check-schema-compat`・`bin/check-alerts`・`bin/check-open-items`・`bin/check-commit-refs`・`bin/test-layers` も通った。分岐の網羅率の警告は 2 件（`lib/demo_reset.rb` の、作り直しが失敗した後に戻せなかったときと、owner の設定が無いときの `ensure`）で、2 件とも example を足した。

手元の Docker（arm64 のホストで linux/arm64 をネイティブに組み立てる）で次を確かめた。QEMU の上の組み立ては CI の `images` のジョブに任せた。

- 2 つのイメージが組み立てられる。Rails のイメージで `SECRET_KEY_BASE_DUMMY=1 bin/rails runner` が eager_load で起動する。画面のイメージは uid 1000 で動き、ログインの画面（`/`）にシードのアカウントを描き、ログインしていない `/supplier/dashboard` を `/` へ移す
- `postgres:18.6` に ConfigMap の初期化のスクリプトを渡すと、2 つのロールが `docker/initdb/01_roles.sql` と同じ属性でできる。引用符と空白を含むパスワードでもログインできる
- migrate のコマンドで、業務の DB の持ち主が所有ロールになる
- 本番のイメージの中で `DemoReset` に偽の Kubernetes の API を渡して 2 回続けて流すと、DB を消して作り直し、シードの世界を作って 1 に戻す。`DEMO_WORLD_ENABLED` 無しの `demo:reset` は入口で止まる。子のプロセスを待つ間に SIGTERM（`docker stop`）を送ると、1 秒以内に web と jobs を 1 に戻して終わる
- web（`bin/rails server`）は `/up` が 200 で、http の `POST /session` が `secure` の Set-Cookie を返す。jobs は async のモードで、スーパーバイザ・ディスパッチャ・スケジューラ・ワーカー 4 つを 1 つのプロセスで登録し、メールを `tmp/mails` に書く

> 参考に、手元の Mac（arm64）の `docker stats` は web 132MiB・jobs 149MiB・postgres 71MiB・frontend 69MiB だった。Raspberry Pi の値は作者が測る（`deploy/README.md`「作者の手順」4）。

PR #60 の CI は、`844c291` で全ジョブが通った（images 25 分 59 秒・test 6 分 1 秒・e2e 4 分 21 秒・frontend 50 秒・lint 38 秒・scan_ruby 19 秒）。`images` のジョブは、マニフェストの描画と kubeconform の照合（4 秒）、Rails のイメージの QEMU の上の組み立て（24 分 47 秒）、本番の環境の起動（26 秒）、画面のイメージの組み立て（13 秒）を通り、PR なので GHCR への push を飛ばした。`5dca71c` の `images` のジョブも通った。Rails のイメージの組み立ては `adr/009`「見直す条件」の 20 分を超えた。2 つの実行が同時に始まり、どちらも GitHub Actions のキャッシュが空のまま組み立てたので、キャッシュが効いた後の時間を見てから判断する（IB-93）。

### 残件の処理

引当先が M41 の行は、着手の前と PR の前に台帳を読んだ。OI-145〜OI-149 は blocked-user のままで、既定で作った（ホスト名 `factory-ops-rails.hayatec.dev`、作り直しは日本時間の 4:30 で猶予 6 時間、資源は見積もりのまま、訪問者の操作はすべて許す、共有のアカウントのログアウトは世代を進めない）。差し替える場所は `deploy/README.md`「作者が決める値」にある。そのため `bin/check-open-items --due M41` は落ちる。M41 で決めたことは OI-168〜OI-176 に judgment で積んだ。実機の確かめ（`deploy/README.md`「作者の手順」1〜6）は M41 の完了条件に入れず、作者が結果を PR か台帳に書くまで公開しない。
