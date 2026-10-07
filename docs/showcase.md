# 見せどころ

このリポジトリが示したいことの一覧である。採用の担当者や面接官は、最初の「3 分の案内」だけを読めば足りる。主張を確かめたいエンジニアは、続くテーマごとの節で、設計判断の文書・守っているコード・確かめるコマンドを辿る。

示したいのは、動く機能の多さではない。設計判断が、コードのどこで、どの仕組みで守られているかを、読み手が自分で辿れることである。題材は、取引関係にある 2 社が同じシステムで発注と受注をつなぐ、相互アクセス型のマルチテナントの B2B SaaS である（`../README.md`）。

各節の「状態」は、実装済みか、`implementation-plan.md` のどのマイルストーンで作る計画かを示す。どこまで実装したかは `handoff.md`「リポジトリの状態」にある。計画のものは、置き場のパスに「（計画：Mxx）」を付け、実装済みとは書かない。

## 3 分の案内

次の 4 つを、この順に開く。どれも実装済みである。

1. **テナントの境界を、表と入口の行列で確かめるテスト**：[`spec/matrix/table_matrix_spec.rb`](../spec/matrix/table_matrix_spec.rb) は、テナントの全表を 5 つのペルソナ（受注側・権限のある発注側・権限の無い発注側・失効した発注側・無関係）で生 SQL から読み書きし、読める行と相手の名義で書けないことを確かめる。[`spec/matrix/graphql_matrix_spec.rb`](../spec/matrix/graphql_matrix_spec.rb) は同じことを GraphQL の全入口で行う。期待値は [`spec/matrix/table_expectations.rb`](../spec/matrix/table_expectations.rb) に表の形で並ぶ。
2. **GraphQL で相手側の型へたどれないことのテスト**：[`spec/graphql/perspective_reachability_spec.rb`](../spec/graphql/perspective_reachability_spec.rb) は、スキーマの型を発注側・受注側の入口からたどり、発注側の視点から受注側の型（受注・在庫・対応表）に届かないことを確かめる。
3. **コンテキストの境界を CI で落とす仕組み**：各パッケージの `package.yml`（例：[`packs/purchasing/package.yml`](../packs/purchasing/package.yml)）が依存してよい先を宣言し、`bin/packwerk check` が CI で依存と非公開のクラスへの参照を落とす。[`spec/packwerk/enforcement_spec.rb`](../spec/packwerk/enforcement_spec.rb) は、違反を一時的に作って検査が実際に落ちることを確かめる。
4. **1 つの操作に整合性の判断が集まる場所**：[`packs/purchasing/app/public/purchasing/ordering.rb`](../packs/purchasing/app/public/purchasing/ordering.rb) の発注の登録は、取引関係の組のロックを取って権限を問い合わせ、発注と「発注登録」のイベントのジョブを同じトランザクションで書く。失効と同時に発注しても、どちらか一方の順にしかならないことを、[`packs/purchasing/spec/public/purchasing/ordering_lock_spec.rb`](../packs/purchasing/spec/public/purchasing/ordering_lock_spec.rb) が 2 つの接続で確かめる。

時間があれば、[`architecture/context-map.md`](architecture/context-map.md) の図と「テナントと所有」の表で業務の全体を、[`adr/`](adr/) で判断の理由を読む。

## テーマごとの詳細

手元で確かめる人は、`../README.md`「開発環境」の手順で DB とテストを準備してから、各節のコマンドを流す。どのテーマでも、CI（`.github/workflows/ci.yml`）は rubocop・`bin/packwerk validate && bin/packwerk check`・rspec・`bin/check-structure`・brakeman を流す。

### 1. テナントの境界：読む 3 経路、書けないこと、失効

**何を示すか**：相手テナントのデータを読める経路は 3 つ（カタログ・取引関係・自社の発注に連結した出荷）に限られ、相手の名義では書けず、取引関係の失効で読む経路と新しい発注が閉じる。

**設計判断**
- [`architecture/context-map.md`](architecture/context-map.md)「テナントと所有」「取引関係の失効」
- [`architecture/data-model.md`](architecture/data-model.md)「テナントの持ち方：全テーブルに共通の規則」「RLS」
- [`architecture/decisions.md`](architecture/decisions.md) 2 章（RLS は粗い判定、可視範囲は policy scope）

**どこで守っているか**
- DB：全表の RLS（`WITH CHECK` で所有テナントに限る）と、3 経路だけに足した `SELECT` のポリシー。表は `lib/tenant_table.rb` の `create_tenant_table` で作る。親子は `owner_tenant_id` を含む複合外部キーでつなぐ
- DB ロール：アプリ・テスト・ワーカーは RLS の掛かる一般ロール `factory_app` で接続する（`lib/tasks/db_roles.rake`）
- テナントの設定：`packs/platform/app/models/tenancy.rb`（`SET LOCAL`）、`packs/platform/app/models/tenant_record.rb`（テナント未設定なら例外）、`config/initializers/tenancy.rb`（接続の貸し出しで空にする）
- 可視範囲：各パッケージの policy の scope と、権限を答える `packs/partnerships/app/public/partnerships/access.rb`
- 存在を明かさない：見えない ID は存在しない ID と同じ `null`・`NOT_FOUND`、発注できない相手はどれも同じ `NOT_PERMITTED`（`app/graphql/mutations/place_purchase_order.rb`）

**どう確かめられるか**

```sh
bundle exec rspec spec/matrix spec/db spec/platform
bundle exec rspec spec/requests/purchase_orders_spec.rb spec/requests/supplier_shipments_spec.rb spec/requests/partnerships_spec.rb
```

- `spec/db/tenant_enforcement_spec.rb`：テスト DB のカタログを引き、RLS・ポリシー・複合外部キーの欠けた表と、RLS を迂回できる接続ロールを落とす
- `spec/platform/tenancy_session_spec.rb`：接続に残ったテナントが次の利用者に漏れない
- `spec/requests/supplier_shipments_spec.rb`：失効すると、権限の付与が残っていても経路 3 が空になり、自社の写しは残る

**状態**：実装済み（3 経路と失効は M8・M9・M14）。失効の後に連結済みの取引が請求まで進むことの通し試験は計画（M26、`spec/scenarios/revocation_spec.rb`）。イベントで知った相手の ID をすべての入口に持ち込むシナリオは計画（M16、`spec/scenarios/tenant_boundary_spec.rb`）。

### 2. コンテキストの境界と依存の向き

**何を示すか**：6 つのコンテキストは、許可した向きにしか依存できず、他のパッケージの公開 API 以外を参照できない。これを初日から CI で強制している。

**設計判断**
- [`adr/002-packwerkを初日からCIで強制する.md`](adr/002-packwerkを初日からCIで強制する.md)
- [`architecture/context-map.md`](architecture/context-map.md)「疎結合を守る規則」（許可する依存の向きの表）
- [`guides/packs-and-packwerk.md`](guides/packs-and-packwerk.md)（違反の読み方と直し方）

**どこで守っているか**
- `packs/*/package.yml`：依存してよい先と、プライバシーの検査
- 公開 API は `packs/*/app/public/` にだけ置く。購買と受注は互いに直接依存せず、イベントだけでつながる
- packwerk が区別できない例外（購買から受注へは `Sales::PublishedCatalog` だけを読む）は、`spec/packwerk/purchasing_uses_only_published_catalog_spec.rb` が守る
- 違反を `package_todo.yml` に逃がさない（`implementation-plan.md`「共通の完了条件」）

**どう確かめられるか**

```sh
bin/packwerk validate && bin/packwerk check
bundle exec rspec spec/packwerk
```

**状態**：実装済み（M2）。

### 3. 責務と関心の分離

**何を示すか**：1 回のリクエストが「コントローラ → GraphQL のリゾルバ・mutation → コンテキストの公開 API → モデル」の順に通り、各層の責務が重ならない。テナントをまたぐ言葉の違いは受け手の側の腐敗防止層が吸収する。

**設計判断**
- [`architecture/graphql-schema.md`](architecture/graphql-schema.md)「1 回のリクエストがたどる道」「読み取りの一覧」「mutation の一覧」
- [`architecture/context-map.md`](architecture/context-map.md)「コンテキスト間の関係」「発注の連結と品番の照合」
- [`architecture/data-model.md`](architecture/data-model.md)「状態は保存せず、時刻列から導出する」
- [`architecture/decisions.md`](architecture/decisions.md)「全体の方針」（リポジトリ層・DTO の詰め替えを採らない）、4 章（手続きクラスは条件を満たす操作にだけ作る）

**どこで守っているか**
- 入口：`app/controllers/graphql_controller.rb` が認証とテナントの設定をし、スキーマの実行全体を 1 つのトランザクションで包む
- GraphQL 層：mutation は公開 API を呼ぶだけで業務規則を持たない（`app/graphql/mutations/place_purchase_order.rb`）。別のコンテキストの値は Dataloader でまとめて公開 API から引く（`app/graphql/sources/public_api_source.rb`）
- 公開 API：操作者を必須の引数に取り、scope を掛けた後に AR のレコードではなく値のオブジェクト（`*_value.rb`）を返す。書く操作と読む問い合わせは別のモジュールに分ける（`Purchasing::Ordering` と `Purchasing::PurchaseOrders`、`Sales::OrderAllocation` と `Sales::SalesOrders`、`Fulfillment::Shipping` と `Fulfillment::ShipmentRequests`）
- 腐敗防止層：`packs/sales/app/public/sales/purchase_order_translator.rb` が、発注側の自社品番を受注側の品目へ読み替えて受注を作る
- 状況の導出：受注・発注・出荷依頼の状況は保存せず、時刻列から導出する（`packs/sales/app/models/sales/sales_order_status.rb`、`packs/purchasing/app/models/purchasing/purchase_order_status.rb`、`packs/fulfillment/app/models/fulfillment/shipment_request_status.rb`）。イベントが想定外の順で届いても遷移表から外れない
- 発注側の写し：発注側は、受注確定の品目名と単価・出荷計上を、自社の表に写して持つ（`packs/purchasing/app/public/purchasing/supplier_event_receiver.rb`、`packs/purchasing/app/models/purchasing/inbound_shipment.rb`）。相手の伝票を読みに行かない

**どう確かめられるか**

```sh
bundle exec rspec packs/sales/spec/models packs/purchasing/spec/models packs/fulfillment/spec/models   # 導出表の行ごとに 1 つ
bundle exec rspec spec/requests/purchase_orders_spec.rb spec/requests/part_mappings_spec.rb          # 腐敗防止層と照合のやり直し
```

**状態**：実装済み（M4・M5・M10・M11・M14）。請求書の写し（受領請求書）は計画（M25）。

### 4. 整合性の設計

**何を示すか**：在庫の不変条件は同期・同一トランザクションで、テナントをまたぐ連結は非同期のイベントで守る。イベントは業務データと同じトランザクションで登録し、受け手は冪等に動き、同時の操作はロックの順で直列になる。

**設計判断**
- [`adr/005-イベントのジョブをトランザクション内で登録する.md`](adr/005-イベントのジョブをトランザクション内で登録する.md)
- [`architecture/context-map.md`](architecture/context-map.md)「コンテキスト間の関係」（同期と非同期の使い分け）、「取引関係の失効」（組のロック）
- [`architecture/data-model.md`](architecture/data-model.md)「イベントの受け口と冪等キー」「取消と出荷の競合を止める場所」

**どこで守っているか**
- イベントの登録：`packs/contracts/app/public/contracts.rb` の `Contracts.publish` だけが、トランザクションの中で `Contracts::EventJob`（`packs/contracts/app/public/contracts/event_job.rb`）を登録する。外で登録するとカスタム Cop `lib/rubocop/cop/factory_ops/event_job_enqueue.rb` と実行時の検査が落とす。outbox は置かない
- 冪等キー：受け手ごとに業務の ID の一意制約で取る（例：受注の `source_purchase_order_id`、`packs/sales/app/public/sales/purchase_order_translator.rb`）
- 在庫の同期：`Inventory::Allocation`（`packs/inventory/app/public/inventory/allocation.rb`）を受注と出荷が同じトランザクションで呼び、有効在庫が負にならないことを行ロックと CHECK 制約で守る
- ロックの順：受注 → 受注明細 → 在庫（`item_id` 昇順、`Inventory::Stock.lock_for`）→ 引当。出荷も在庫から先を同じ順で取り、デッドロックを起こさない
- 引当の行を直列化の点にする：出荷の計上は `active` の引当だけを消費し、受注の取消は消費済みの引当を解除しない。同時に進んでもどちらか一方だけが成立する
- 組の勧告ロック：`Partnerships::Access.lock_pair!` が、受注側と発注側の組ごとに PostgreSQL の勧告ロック（`pg_advisory_xact_lock`）を取り、発注の登録と、取引関係の失効・権限の撤回を直列にする。照合と対応表の登録は `Sales::PartMatching.lock`（`packs/sales/app/models/sales/part_matching.rb`）で直列にする

**どう確かめられるか**

```sh
bundle exec rspec spec/jobs/event_job_atomicity_spec.rb spec/contracts spec/rubocop
bundle exec rspec packs/purchasing/spec/public/purchasing/ordering_lock_spec.rb \
  packs/sales/spec/public/sales/order_allocation_lock_spec.rb packs/sales/spec/public/sales/part_mappings_spec.rb
bundle exec rspec packs/sales/spec/public/sales/order_allocation_spec.rb packs/fulfillment/spec/public/fulfillment/shipping_spec.rb
```

- `spec/jobs/event_job_atomicity_spec.rb`：キューの接続が業務 DB と同じで、ロールバックすればジョブも残らない
- `spec/support/shared_examples/idempotent_receiver.rb`：同じイベントを 2 回発行し、同じジョブを 2 回実行しても、書いた行が増えない。受け手ごとに適用する
- `order_allocation_spec.rb`・`shipping_spec.rb`：発行された `FOR UPDATE` を記録し、ロックの順を確かめる

**状態**：実装済み（M7・M10〜M14）。引当の行で取消と出荷の同時実行を止めることのテストは計画（M22、`spec/concurrency/`）。

### 5. 非同期処理の型の使い分け

**何を示すか**：非同期処理を「ジョブを失ったときに誰が気づけるか」で 5 つの型（トランザクション内のイベント・確実な外部送信・撃ちっぱなし・inbox・再開できる長時間のジョブ）に分け、型ごとに登録の時機・再試行・冪等・失敗の扱いを決める。

**設計判断**
- [`adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md`](adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md)
- [`architecture/decisions.md`](architecture/decisions.md) 5 章

**どこで守っているか**
- トランザクション内のイベント：テーマ 4 のとおり実装済み
- 外部への作用の登録口を 1 つにする基底クラス `ExternalEffectJob` と、カスタム Cop `FactoryOps/ExternalEffectEnqueue`（計画：M28）
- SendGrid のメール：確実な外部送信（送信記録 `email_deliveries` で重複を避ける）と撃ちっぱなし、配信結果の Webhook を受ける inbox（`webhook_inbox_events`）を `packs/notifications` に置く（計画：M28）
- CSV の取り込み：Active Job Continuations で中断から再開し、専用のキューで他の処理を待たせない（計画：M29、`packs/imports`）

**どう確かめられるか**：`spec/notifications/call_sites_spec.rb`（通知の種類ごとに呼び出し元が 1 か所）と、`event_job_atomicity_spec.rb` を広げた登録の時機の検査（どちらも計画：M28）。テストと開発では WebMock で本物の SendGrid を呼べなくする。

**状態**：イベントの型だけ実装済み（M7）。残りの 4 つの型は計画（M28・M29）。

### 6. GraphQL の安全な形

**何を示すか**：1 つのスキーマを発注側と受注側の視点に分け、汎用の `node` を置かず、宣言の無い型・リゾルバ・mutation を拒否する。相手側へたどれないことをテストで固定する。

**設計判断**
- [`adr/004-GraphQLの型を視点ごとに分けnodeを置かない.md`](adr/004-GraphQLの型を視点ごとに分けnodeを置かない.md)
- [`architecture/graphql-schema.md`](architecture/graphql-schema.md)「視点ごとに型を分ける」「ID と `node`」「認可：宣言の無い型・リゾルバ・mutation は拒否する」「スキーマの変更と非推奨」

**どこで守っているか**
- 視点の宣言と認可の宣言：基底クラス `app/graphql/types/base_object.rb`・`app/graphql/resolvers/base_resolver.rb`・`app/graphql/mutations/base_mutation.rb` と `app/graphql/authorization_declarations.rb`。宣言が無ければ開発とテストで例外、本番で `FORBIDDEN`
- `node` を置かない：`app/graphql/factory_ops_schema.rb` の `object_from_id` は呼ばれたら例外にする。ID で引く入口は視点の下に型ごとに置く
- 問い合わせの深さと複雑度の上限：同じく `app/graphql/factory_ops_schema.rb`
- スキーマの破壊的変更：`schema.graphql` を commit し、`bin/check-schema-compat` が非推奨を経ない削除を CI で落とす（計画：M20）

**どう確かめられるか**

```sh
bundle exec rspec spec/graphql spec/matrix/graphql_matrix_spec.rb
```

- `perspective_reachability_spec.rb`：発注側から受注側の型へたどれず、相手のデータを返す型が 3 経路の 3 つに限られる
- `authorization_declarations_spec.rb`：全型・全リゾルバ・全 mutation が宣言を持ち、認可の例外が `graphql-schema.md` の表と一致する
- `base_classes_spec.rb`：宣言の無いものを拒否し、拒否を `FORBIDDEN` に揃える

**状態**：視点・`node` の不在・宣言の強制は実装済み（M5・M6）。スキーマの差分の検査は計画（M20、`spec/graphql/schema_dump_spec.rb`）。

### 7. 時間の扱い：販売単価のバイテンポラル履歴

**何を示すか**：販売単価を有効期間と記録期間の 2 軸で持ち、行を書き換えない。改定を前もって登録でき、誤りを過去の行を消さずに訂正でき、発行済みの請求書について「発行の時点で信じていた単価」と「いま分かっている単価」を並べて示せる。

**設計判断**：[`adr/006-販売単価を有効期間と記録期間の2軸で持つ.md`](adr/006-販売単価を有効期間と記録期間の2軸で持つ.md)

**どこで守っているか**（すべて計画：M27）
- `item_prices` の排他制約：記録期間が終わっていない行同士で、有効期間が重ならない
- トリガー：記録期間を閉じる以外の UPDATE と、すべての DELETE を拒む
- 単価の問い合わせを 1 つの公開 API `Sales::ItemPrices.price_at`（有効日と記録時点の 2 引数）に集める

**どう確かめられるか**：`packs/sales/spec/db/item_prices_constraints_spec.rb`、`packs/sales/spec/public/sales/item_prices_spec.rb`（どちらも計画：M27）

**状態**：計画（M27）。

### 8. 機械で守る規約

**何を示すか**：破ると事故になる規約だけを、文書ではなくテスト・Cop・基底クラス・DB の制約で守る。規約を README にだけ書いて終えない。

**設計判断**
- [`architecture/decisions.md`](architecture/decisions.md)「全体の方針：Rails の構造を使い切り、事故になる 4 か所だけを機械で守る」、7 章（規約ごとの守る手段の表）
- [`adr/001-スキーマ管理にridgepoleを採用しない.md`](adr/001-スキーマ管理にridgepoleを採用しない.md)、[`adr/003-主キーにUUIDv7を使う.md`](adr/003-主キーにUUIDv7を使う.md)

**どこで守っているか**

| 規約 | 守る仕組み | 状態 |
|---|---|---|
| テナントの表は必ず `owner_tenant_id` を持つ | 列挙テスト `spec/db/tenant_columns_spec.rb`（持たない表は理由付きで宣言） | 実装済み |
| 型・リゾルバ・mutation は認可を宣言する | 基底クラスの実行時のゲートと、列挙テスト `spec/graphql/authorization_declarations_spec.rb` | 実装済み |
| イベントの配送表の受け手が実在する | `spec/contracts/subscriptions_spec.rb` | 実装済み |
| 全表・全入口がペルソナごとの期待値を持つ | 行列テスト `spec/matrix/`（期待値の無い表があれば落ちる） | 実装済み |
| イベントのジョブを `Contracts.publish` の外で登録しない | カスタム Cop `FactoryOps/EventJobEnqueue` | 実装済み |
| 主キーは DB の `uuidv7()` で作る | `spec/db/uuidv7_default_spec.rb` | 実装済み |
| マイグレーションの結果と `structure.sql` が一致する | `bin/check-structure`（migrate と load の両経路を比べる） | 実装済み |
| コメントに経緯・マイルストーンの番号を書かない | カスタム Cop `FactoryOps/NoHistoryComment` | 計画：M15 |
| N+1 を作らない | Bullet と、画面の問い合わせごとのクエリ数の予算 `spec/graphql/query_budget_spec.rb` | 計画：M17 |

守りの検査は、外すとテストが落ちることを確かめてから戻す（`handoff.md`「1 つのマイルストーンの回し方」）。

**どう確かめられるか**

```sh
bin/rubocop
bundle exec rspec spec/db spec/graphql spec/contracts spec/matrix spec/rubocop
bin/check-structure
```

**状態**：表のとおり。

### 9. テスト戦略

**何を示すか**：テストの大半を、速く、落ちた場所から原因が分かる単体テスト（公開 API・モデル・policy）に置き、壊れると事故になる流れだけを専用のシナリオテストで端から端まで確かめる。テストは本番と同じ仕組みの上で動かす。

**設計判断**
- [`implementation-plan.md`](implementation-plan.md)「M16 テストの層と重要シナリオ」
- [`adr/005-イベントのジョブをトランザクション内で登録する.md`](adr/005-イベントのジョブをトランザクション内で登録する.md) 決定 6（テストでも Active Job の `:test` アダプタに差し替えない）

**どこで守っているか**
- 単体は `packs/*/spec`、結合は `spec/requests`・`spec/contracts` に置く
- テストは RLS の掛かる `factory_app` で接続するので、RLS を迂回しない（`spec/db/tenant_enforcement_spec.rb`「接続中のロール」）
- イベントは `:solid_queue` のまま `solid_queue_jobs` の行を読んで受け手まで流す（`spec/support/events.rb` の `deliver_enqueued_events`）
- 同時実行は、2 つの接続を別のスレッドで動かして確かめる（`ordering_lock_spec.rb`・`order_allocation_lock_spec.rb`・`part_mappings_spec.rb`）
- 層の定義 `config/test_layers.yml` と、層ごとの件数を CI で報告する `bin/test-layers`（計画：M16）
- 重要シナリオ S1〜S5（テナントの境界・失効・連結・競合・請求の金額）を `spec/scenarios`・`spec/concurrency` に置き、`--tag scenario` で単独で流す（計画：M16〜M25）

**どう確かめられるか**

```sh
bundle exec rspec packs        # 単体
bundle exec rspec spec/requests spec/contracts   # 結合
```

**状態**：本番と同じ仕組みで動かすことと同時実行のテストは実装済み。層の報告と重要シナリオは計画（M16、S2 は M26、S5 は M25）。

### 10. 運用性

**何を示すか**：障害の原因をログだけで辿れ、テナントをまたぐ一連の処理を 1 つの相関 ID で引ける。相手テナントに効果が及ぶ書き込みは監査ログに必ず残る。主な操作に SLO があり、どの警報からも手順書へたどれる。

**設計判断**
- [`implementation-plan.md`](implementation-plan.md)「M18 構造化ログと相関 ID」「M19 監査ログ」「M30 メトリクス」「M31 SLO と障害対応の手順書」
- [`architecture/data-model.md`](architecture/data-model.md)「監査ログ（`platform`）」、[`architecture/graphql-schema.md`](architecture/graphql-schema.md)「監査ログ」

**どこで守っているか**（すべて計画）
- 構造化ログ：`Rails.event` を出口にした 1 行 1 件の JSON。`Contracts.publish` がイベントの付帯情報で相関 ID と因果 ID を運ぶ。個人情報と自由記述を書かない（M18）
- 監査ログ：mutation とイベントのジョブの基底クラスが記録し、表は追記だけ（M19）
- メトリクス：Yabeda と Prometheus。ラベルにテナントとユーザーを入れない（M30）
- SLO と手順書：`docs/slo.md`・`docs/runbooks/`・`config/prometheus/alerts.yml`（M31）

**どう確かめられるか**：`spec/contracts/correlation_spec.rb`・`spec/requests/log_hygiene_spec.rb`（M18）、`spec/db/audit_logs_spec.rb`・`spec/requests/audit_spec.rb`（M19）、`spec/platform/metrics_subscriber_spec.rb`（M30）、`spec/platform/alerts_runbook_spec.rb`（M31）。どれも計画である。

**状態**：計画（M18・M19・M30・M31）。

### 11. チーム開発

**何を示すか**：人が入れ替わっても、判断の理由と現在地が文書から辿れる。判断は「既定の推奨・裏返る条件・撤退コスト」の形で残し、コメントは古い経緯で読む人を誤らせない。

**設計判断と置き場**
- 設計判断の一般原則：[`architecture/decisions.md`](architecture/decisions.md)（各論点の既定の推奨・裏返る条件・撤退コスト）
- 個別の判断：[`adr/`](adr/)（ステータス・コンテキスト・決定・結果・代替案の形。設計文書と食い違えば ADR が優先する）
- 現在地と次の一手：[`handoff.md`](handoff.md)（決まったこと・決まっていないこと・次にやること）
- 実装の順と完了条件：[`implementation-plan.md`](implementation-plan.md)（マイルストーンごとに、機械で守るようになる規則と完了条件のコマンドを書く）
- コメントの規約：[`guides/comments.md`](guides/comments.md)（いまの振る舞いと理由だけを書き、根拠を設計文書の節で指す）
- 生成物から変えたことの解説：[`guides/bin.md`](guides/bin.md)・[`guides/config.md`](guides/config.md)・[`guides/packs-and-packwerk.md`](guides/packs-and-packwerk.md)

**どう確かめられるか**：コードのコメントと spec の冒頭は、根拠を設計文書の節で指している（例：`packs/purchasing/app/public/purchasing/ordering.rb`、`spec/graphql/perspective_reachability_spec.rb`）。

**状態**：文書は実装済み。コメントの規約を Cop で止めることは計画（M15）。
