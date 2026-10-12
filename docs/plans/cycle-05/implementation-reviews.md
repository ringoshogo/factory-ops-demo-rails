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

2 つの守りが同じ条件を持つのは、副問い合わせの scope と RLS、出荷停止の所有テナントのそろえと RLS である。どちらも RLS を開かない限り他社の行が見えないので、式の側を壊したときは RLS を開いた単体だけが落ち、行列は落ちない。RLS の側を壊すのは表の行列（`table_matrix_spec.rb`）が確かめる。

テストの基盤として足したものは、`MatrixWorld#add_filter_rows` の取消済と取消していない受注・発注と、取消済の出荷依頼である。出荷依頼の `statuses` を外すと、行列の「変種の行が世界を絞る」確かめが落ちる（上の表）。受注と発注は受注日・発注日でも絞るので、状況を外しても行列のこの確かめは落ちず、状況の spec が落とす。

### 確かめたこと

`ae7adbb` のコードで、Ruby 3.4.11 で M40 の完了条件と共通の完了条件を流した。この worktree では `bin/ci` の Setup の工程が落ちる（IB-72）ので、`config/ci.rb` の Setup のほかの工程を同じコマンドで 1 つずつ流した。

```sh
bundle exec rspec <完了条件の 1 つ目のコマンド>      # 10 examples, 0 failures
bundle exec rspec <完了条件の 2 つ目のコマンド>      # 30 examples, 0 failures
bundle exec rspec <完了条件の 3 つ目のコマンド>      # 1445 examples, 0 failures
bin/check-schema-compat                              # 落とす変更なし（足したのは省いてよい引数と型だけ）
COVERAGE=1 bundle exec rspec                         # 2746 examples, 0 failures（2 分 16 秒）
BASE_REF=origin/main bin/check-branch-coverage       # 一覧は空
bin/check-open-items --due M40                       # 終了コード 0
bundle exec rspec --tag concurrency                  # 2 回続けて 61 examples, 0 failures
```

rubocop・packwerk・brakeman・bundler-audit・`bin/check-structure`・`bin/check-alerts`・`bin/check-commit-refs`・`bin/test-layers` も通った。分岐の網羅率の警告は 0 件で、example を足した件数も 0 件である。

行列の spec の時間（手元、`bundle exec rspec <ファイル>` を 2 回ずつ、`ae7adbb`）は、`graphql_matrix_spec.rb` が 578 examples で 10.17 秒・9.49 秒、`table_matrix_spec.rb` が 804 examples で 7.30 秒・7.17 秒である。M39 の記録（577 examples、9.11 秒・9.40 秒）より入口の行列が 1 example と 1 秒弱増えた。2 ファイルを合わせて約 17 秒で、IB-50 の調べ直す条件（合わせて 30 秒を超える）には当たらない。

### 残件の処理

引当先が M40 の行は、着手の前と PR の前に台帳を読み、無かった。OI-07 の作者の判断（サーバーで並べ替えと絞り込み、件数）の残り（状況での絞り込み）をこの PR で反映した。OI-144（並べ替えの列を一覧の表の列に限る）は、状況での並べ替えを足さず既定のまま進めた（引当先は M33）。実装で決めたことは OI-158〜OI-160 に judgment で積んだ。
