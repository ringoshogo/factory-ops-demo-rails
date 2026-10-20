# packs と packwerk

このリポジトリを開くと、業務のモデルが `app/models/` ではなく `packs/<パッケージ>/app/` の下にある。この文書は、Rails の基本は知っているが packwerk に慣れていない開発者が、なぜこう分けたのか、どの道具が何をしているのか、違反したときに何が起き、どう直すのかを、このリポジトリのコードで追えるようにする。判断の記録は [ADR 002](../adr/002-packwerkを初日からCIで強制する.md) にある。

## なぜパッケージに分けるか

Rails のアプリは、どのクラスからどのクラスでも呼べる。受注のコードが在庫の AR モデルを直接書き換えても、Rails は止めない。そうした近道が積み重なると、在庫の不変条件（有効在庫が負にならない、など）を守る場所が 1 か所でなくなり、どこを直せば何が壊れるかが読めなくなる。

本デモは、業務を 6 つのコンテキスト（取引関係・購買・受注・在庫・出荷・請求）に分け（[context-map.md](../architecture/context-map.md)）、それぞれを 1 つのパッケージにする。パッケージに分けると、次の 2 つを機械で検査できる。

- **依存の向き**：あるパッケージが参照してよい先を、`package.yml` に宣言したパッケージに限る。
- **公開 API**：他のパッケージから参照してよいクラスを、各パッケージの `app/public/` に置いたものに限る。

どちらも、違反すると CI が落ちる。規則を文書に書くだけでは、守られていることを読み手が確かめられない。

## packs/ に並ぶもの

`packs/` の下には 10 のパッケージがある。6 つのコンテキストに、イベントの置き場 `contracts`、Rails の基底クラスの置き場 `platform`、外部へのメールの送信 `notifications`、CSV の取り込み `imports` を足したものである。

| パッケージ | 中身 | 公開 API の例（`app/public/`） |
|---|---|---|
| `platform` | `ApplicationRecord`・`ApplicationJob`・`ExternalEffectJob`・`ApplicationMailer`・`TenantRecord`・`Current`・`Tenancy` などの基底クラスとテナントの仕組み、監査ログ（`AuditLog`・`Platform::AuditLogs`）、構造化ログの基盤（`Platform::Logging`・文脈のミドルウェア） | （公開を限定しない） |
| `contracts` | コンテキスト間のイベントと、その配送（`Contracts.publish`・`EventJob`・配送表 `Subscriptions`） | すべて `app/public/` にある |
| `partnerships` | テナント・ユーザー・取引関係・権限付与 | `Partnerships::Actor`・`Authentication`・`Access` |
| `purchasing` | 発注と入荷 | `Purchasing::Ordering`・`PurchaseOrders` |
| `sales` | 品目・受注・品番の対応表 | `Sales::OrderAllocation`・`PublishedCatalog` |
| `inventory` | 在庫・引当・在庫の移動 | `Inventory::Allocation`・`Stocks` |
| `fulfillment` | 出荷依頼・出荷指示・出荷 | `Fulfillment::Shipping`・`PartnerShipments` |
| `billing` | 請求条件・請求対象明細・請求書（締め・下書きの破棄・確定） | `Billing::Closing`・`Invoices` |
| `notifications` | メールの送信記録と送信のジョブ、配信結果の Webhook の受信（[ADR 007](../adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md)） | `Notifications::Email`・`Inbox` |
| `imports` | 取り込みのファイル・取り込み・置き場の行と、取り込みのジョブ | `Imports::Files`・`Runs` |

GraphQL の層（`app/graphql/`）やコントローラなど、どのコンテキストにも属さないコードは、リポジトリの直下の `app/` に置く。直下はルートパッケージ（`package.yml` がリポジトリの直下にある、名前が `.` のパッケージ）に属する。直下の `lib/`（シードと E2E の世界を作る `DemoWorld`、カスタム Cop など）も同じルートパッケージに属し、packwerk はほかのパッケージの非公開の定数への参照を落とす。`DemoWorld` が公開 API だけで世界を作ることは、この検査が守る。

各パッケージが依存してよい先は、[context-map.md「疎結合を守る規則」](../architecture/context-map.md#疎結合を守る規則) の「許可する依存の向き」の表が正本である。各 `package.yml` の `dependencies` は、この表と一致させる。表の要点は次の 3 つ。

- 購買（`purchasing`）と受注（`sales`）は直接依存しない。発注と受注の連結はイベントで行う。例外は、購買が受注の `Sales::PublishedCatalog` を読むことだけである。
- `platform` はどこにも依存しない。`partnerships` と `contracts` は `platform` だけに依存する。
- ルートパッケージはすべてのパッケージに依存してよい。

## 2 つの道具：packs-rails と packwerk

パッケージの仕組みは、役割の違う 2 つの gem で成り立つ。

| | packs-rails | packwerk（＋packwerk-extensions） |
|---|---|---|
| 働く時機 | アプリの起動時とテストの実行時 | `bin/packwerk check` を流したとき（CI と手元） |
| すること | `packs/*/app/*` を Rails の自動読み込みの対象に足す。`packs/*/spec` を RSpec の対象に、`packs/*/spec/factories` を FactoryBot の定義の置き場に足す | ソースを構文解析して定数の参照を集め、参照元と参照先のパッケージを `package.yml` と照らして違反を報告する |
| 設定 | `.rspec` の `--require packs/rails/rspec` | `packwerk.yml`（直下）と各 `package.yml` |

packs-rails があるので、`packs/inventory/app/models/inventory/stock.rb` は `Inventory::Stock` として読み込まれる。`app/models/` と `app/public/` は、どちらも自動読み込みの起点になる。そのため、`packs/inventory/app/public/inventory/allocation.rb` も `Inventory::Allocation` で、ファイルを `app/models/` と `app/public/` の間で移しても定数名は変わらない。

packwerk は静的な検査だけを行い、実行時には何もしない。`bin/rails console` や実行中のアプリからは、どのパッケージの非公開のクラスでも参照できてしまう。境界を守らせるのは、CI の `bin/packwerk check` である。

## 1 つのパッケージの中身

`packs/inventory` を例にとる。

```text
packs/inventory/
├── package.yml                       # このパッケージの宣言
├── app/
│   ├── models/inventory/             # 非公開。AR モデルと内部の部品
│   │   ├── stock.rb                  #   Inventory::Stock
│   │   ├── stock_allocation.rb
│   │   ├── stock_movement.rb
│   │   └── scope.rb
│   └── public/inventory/             # 公開 API。他のパッケージが参照してよいのはここだけ
│       ├── allocation.rb             #   Inventory::Allocation（引当）
│       ├── stocks.rb                 #   Inventory::Stocks（在庫の読み取り）
│       ├── stock_value.rb            #   Inventory::StockValue（読み取り用の値）
│       └── stock_policy.rb
└── spec/
    ├── factories/inventory.rb        # このパッケージのモデルのファクトリ
    ├── models/inventory/stock_spec.rb
    └── public/inventory/allocation_spec.rb
```

ファイルがどのパッケージに属するかは、ファイルから親のディレクトリへたどって最初に見つかる `package.yml` で決まる。`packs/inventory/spec/` の下は `packs/inventory` に属し、リポジトリの直下の `spec/` はルートパッケージに属する。

### package.yml の項目

```yaml
# packs/inventory/package.yml
enforce_dependencies: strict
enforce_privacy: strict
dependencies:
  - packs/platform
  - packs/partnerships
```

| 項目 | 意味 | 本デモでの値 |
|---|---|---|
| `enforce_dependencies` | このパッケージから外への参照を、`dependencies` に宣言した先に限る | 全パッケージで `strict` |
| `dependencies` | 参照してよいパッケージの一覧。循環すると `bin/packwerk validate` が落ちる | context-map.md の表のとおり |
| `enforce_privacy` | 他のパッケージからこのパッケージへの参照を、`app/public/` の下の定数に限る。packwerk-extensions の機能で、`packwerk.yml` の `require: packwerk/privacy/checker` で有効にしている | `platform` 以外の 9 つで `strict` |

`strict` は、`true` より強い。`true` なら、既存の違反を `package_todo.yml`（違反の一時的な許容リスト）に記録して見逃せる。`strict` では記録できず、違反はその場で直すしかない（ADR 002 決定 5）。本リポジトリに `package_todo.yml` は無い。

`platform` は `enforce_privacy` を持たない。どのパッケージのモデルも `ApplicationRecord` などを継承するので、`platform` の中身はすべて公開と同じに扱う。一方で `dependencies` を持たないので、`platform` からは他のパッケージを参照できない。

ルートパッケージの `package.yml` は `enforce_dependencies: strict` で、10 のパッケージすべてを `dependencies` に並べる。ルートからは全パッケージに依存してよいが、プライバシーの検査はルートからの参照にも掛かる。

## 2 つの検査

packwerk は、定数の参照 1 つごとに 2 つの問いを順に確かめる。参照元のパッケージは、参照先のパッケージへの依存を宣言しているか（依存の検査）。参照先の定数は、参照先のパッケージの `app/public/` にあるか（プライバシーの検査）。

### 通る参照

受注の引当は、在庫の引当を呼ぶ（`packs/sales/app/public/sales/order_allocation.rb`）。

```ruby
before = Inventory::Allocation.quantities_for(actor, lines.map(&:id))
```

`packs/sales/package.yml` は `packs/inventory` への依存を宣言しており、`Inventory::Allocation` は `packs/inventory/app/public/` にある。どちらの検査も通る。

### 依存の違反

購買のコードが在庫の公開 API を参照したとする。`Inventory::Stocks` は公開 API だが、`packs/purchasing/package.yml` は `packs/inventory` への依存を宣言していない。

```ruby
# packs/purchasing/app/models/purchasing/zz_probe.rb（仮のファイル）
module Purchasing
  class ZzProbe
    def call = Inventory::Stocks
  end
end
```

`bin/packwerk check` は次のように報告し、終了コード 1 で終わる。

```text
packs/purchasing/app/models/purchasing/zz_probe.rb:3:15
Dependency violation: ::Inventory::Stocks belongs to 'packs/inventory', but 'packs/purchasing' does not specify a dependency on 'packs/inventory'.
Are the constant and its references in the right packages?

Inference details: this is a reference to ::Inventory::Stocks which seems to be defined in packs/inventory/app/public/inventory/stocks.rb.
```

### プライバシーの違反

受注のコードが在庫の AR モデルを直接参照したとする。`packs/sales` は `packs/inventory` に依存してよいが、`Inventory::Stock` は `app/models/` にあり、公開されていない。

```ruby
# packs/sales/app/models/sales/zz_probe.rb（仮のファイル）
module Sales
  class ZzProbe
    def call = Inventory::Stock
  end
end
```

```text
packs/sales/app/models/sales/zz_probe.rb:3:15
Privacy violation: '::Inventory::Stock' is private to 'packs/inventory' but referenced from 'packs/sales'.
Is there a public entrypoint in 'packs/inventory/app/public/' that you can use instead?

Inference details: this is a reference to ::Inventory::Stock which seems to be defined in packs/inventory/app/models/inventory/stock.rb.
```

この参照を許すと、受注が在庫の数量を直接書き換え、在庫の不変条件を守る `Inventory::Allocation` を迂回できる。止めたいのはこれである（ADR 002 代替案 B）。

違反を `bin/packwerk update-todo` で許容リストに入れようとしても、`strict` なので次の行が出て記録されない。

```text
packs/sales cannot have privacy violations on packs/inventory because strict mode is enabled for privacy violations in the enforcing package's package.yml
```

> 上の出力は、仮のファイルを置いて packwerk 3.3.1・packwerk-extensions 0.4.0 で `bin/packwerk check <ファイル>` を流して得た（色の制御文字は除いた）。

## CI で落ちる場所

パッケージの境界は、次の 5 つで検査する。

| 検査 | 落ちる条件 | 流す場所 |
|---|---|---|
| `bin/packwerk validate` | `package.yml` の書式の誤り、存在しないパッケージへの依存、依存の循環 | GitHub Actions の `lint`、`bin/ci` |
| `bin/packwerk check` | 依存の違反、プライバシーの違反 | 同上 |
| `spec/packwerk/enforcement_spec.rb` | packwerk が違反を検出しなくなったとき。一時ファイルで依存の違反とプライバシーの違反を作り、`bin/packwerk check` が失敗することを確かめる | rspec |
| `spec/packwerk/dependency_table_spec.rb` | `context-map.md`「疎結合を守る規則」の依存の向きの表と、各 `package.yml` の `dependencies` の集合が食い違うとき | rspec |
| `spec/packwerk/purchasing_uses_only_published_catalog_spec.rb` | `packs/purchasing` の中に、`Sales::PublishedCatalog` 以外の `Sales::` の定数への参照があるとき | rspec |

`enforcement_spec.rb` は、検査の仕組みそのもの（`packwerk.yml` の `require` や `package.yml` の `strict`）が誰かに外されたときに落ちる。`bin/packwerk check` は違反が無ければ通るので、仕組みが外れていても気づけないからである。

`purchasing_uses_only_published_catalog_spec.rb` は、packwerk が区別できない範囲を受け持つ。packwerk はパッケージ単位で依存を判定するので、`purchasing` から `sales` への依存を宣言すると、`sales` の公開 API のどのクラスでも参照できる。このテストは Prism（Ruby の構文解析器）で `packs/purchasing` の定数の参照を集め、`Sales::PublishedCatalog` 以外を落とす。

## 層ごとの責務

コードを足す人と、計画・実装・逸脱を検査するレビュアーは、判断と不変条件をどの層に置くかを次の表で決める。パッケージの境界は packwerk が守るが、同じパッケージの中のどの層に判断を置くかは packwerk には見えない。置く層を誤ると、同じ規則を守る場所が 2 つになり、片方の入口（CSV の取り込み・シード・ジョブ）が規則の外に残る。

| 層 | 置くもの | 置かないもの | 守る仕組み |
|---|---|---|---|
| GraphQL のリゾルバと mutation（`app/graphql/resolvers/`・`app/graphql/mutations/`） | 視点・規則・監査の宣言。対象を公開 API で引く `find_target` と、公開 API を呼ぶ `perform` | 業務の判断と不変条件（品目が自社のものか、など）。役割の判断 | 宣言の列挙テスト `spec/graphql/authorization_declarations_spec.rb` と入口の行列 `spec/matrix/graphql_matrix_spec.rb`（[graphql-schema.md「基底クラス」](../architecture/graphql-schema.md#基底クラス)） |
| 型（`app/graphql/types/`） | 公開 API の値を包んで委譲する。役割で見せ方が変わるフィールドは、policy の規則を操作者で評価し、偽なら空を返すだけにする | 並べ替えと件数の上限。役割の判断（`user.admin?` を型に直に書く） | 入口の行列の `member` の行（`viewer.partnerCode`）。並べ替えと上限を型に置かないことは、機械では落とさず、レビューが見る（[graphql-schema.md「役割による制限」](../architecture/graphql-schema.md#役割による制限)・「読み取りの一覧」） |
| policy（`packs/*/app/public/` の `*Policy`） | 可視範囲の scope と、操作ごとの規則。役割の判断はここだけに置く | 業務の不変条件（出荷済みの受注の取消の拒否など） | 入口の行列（[graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」](../architecture/graphql-schema.md#認可宣言の無い型リゾルバmutation-は拒否する)） |
| 公開 API（`packs/*/app/public/`） | 持ち主のコンテキストの業務の判断と不変条件（在庫は自社の品目にだけできる、など）。scope を掛けた読み取り。値・ID・件数・`OperationResult`・`Page`・`SqlSubquery` を返す | relation とモデルを返すこと。不変条件を呼ぶ側に任せること | 戻り値のガード `spec/support/public_api_returns.rb`（`spec/platform/public_api_returns_spec.rb`）と packwerk（[ADR 002](../adr/002-packwerkを初日からCIで強制する.md)、[data-model.md「在庫（`inventory`）」](../architecture/data-model.md#在庫inventory)） |
| イベントの受け手（配送表の受け手の `handle`） | テナントをまたぐ連結の受け口。相手の言葉を自コンテキストの言葉に読み替えた後に、自コンテキストの操作を呼ぶ。`EventJob` からだけ呼ばれる | 同じテナントの中のコンテキストの連結。同じテナントの中は同期の呼び出しでつなぎ、イベントにするのはテナントをまたぐ連結と「出荷可能」だけである | `EventJob` からだけ呼ばれることは、受け手の参照の検査 `spec/packwerk/entry_callers_spec.rb` が落とす。同じテナントの中を同期でつなぐことは機械では落とさず、計画レビューと実装レビューが見る（[ADR 012](../adr/012-同じテナントの中の連結を同期にし出荷可能だけをイベントで残す.md)、[context-map.md「コンテキスト」](../architecture/context-map.md#コンテキスト)） |
| 操作者のいない入口の公開 API | テナントの設定を求め、所有の条件を `Current.tenant_id` で書く操作。表に書いた場所からだけ呼ばれる | 表の場所の外からの呼び出し | 同じ `spec/packwerk/entry_callers_spec.rb`（[graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」](../architecture/graphql-schema.md#認可宣言の無い型リゾルバmutation-は拒否する) の表） |
| ルートパッケージの `lib/`（`DemoWorld`・rake タスク・`DemoReset`） | 公開 API だけを使って世界を作り、運用の操作を流す。`admin` に限る操作は `DemoWorld::Operations` を通し、mutation の宣言の規則を評価する | 非公開の定数の参照。policy と規則の名前の書き写し | packwerk と `spec/scenarios/demo_world_spec.rb`（[graphql-schema.md「役割による制限」](../architecture/graphql-schema.md#役割による制限)） |

> 2026-10-16 の監査で、取引関係の relation を返す公開 API、在庫の不変条件を呼ぶ側の 2 か所が守る形、同じテナントの中の受注から出荷への非同期が、照らす一覧の無いままレビューを通っていた。

## よくある作業の手順

### 新しいパッケージを足す

コンテキストを足す開発者は、次の順に進める。

1. [context-map.md](../architecture/context-map.md) の「許可する依存の向き」の表に、新しいパッケージと依存してよい先を書く。
2. `packs/<名前>/package.yml` を作り、`enforce_dependencies: strict`・`enforce_privacy: strict`・`dependencies` を書く。`dependencies` には少なくとも `packs/platform` を入れる。
3. リポジトリの直下の `package.yml` の `dependencies` に `packs/<名前>` を足す。足さないと、GraphQL の層から新しいパッケージを呼べない。
4. コードを `packs/<名前>/app/models/<名前>/`（非公開）と `packs/<名前>/app/public/<名前>/`（公開 API）に置く。packs-rails は起動時にパッケージを探すので、起動中のサーバーやコンソールは再起動する。
5. テストを `packs/<名前>/spec/`、ファクトリを `packs/<名前>/spec/factories/` に置く。
6. `bin/packwerk validate && bin/packwerk check` を流す。

### 依存を足す

あるパッケージから別のパッケージを呼ぶ必要が出た開発者は、まず context-map.md の表がその向きを許しているかを確かめる。許していなければ、`package.yml` を書き換える前に、表を変えてよいかを設計の判断として決める。購買と受注の間のように、イベントでつなぐと決めた向きを、依存で近道しない。

表を変えたら、`package.yml` の `dependencies` に足し、`bin/packwerk validate` で循環が無いことを確かめる。たとえば `inventory` から `sales` への依存を足すと、`sales` が `inventory` に依存しているので循環になる。

### 公開 API を出す

他のパッケージから呼ばれる入口を作る開発者は、次の形に揃える（[ADR 002](../adr/002-packwerkを初日からCIで強制する.md) 決定 4、[graphql-schema.md「1 回のリクエストがたどる道」](../architecture/graphql-schema.md#1-回のリクエストがたどる道) 3）。

- **置き場**：`packs/<パッケージ>/app/public/<パッケージ>/` に置く。
- **名前**：`app/models/<パッケージ>/` と `app/public/<パッケージ>/` は同じ名前空間に入るので、公開 API のモジュールをモデルと同じ名前にできない。モデルの名前の複数形にする（`Sales::SalesOrders`・`Purchasing::ReceiptInspections`）。
- **返す値**：AR モデルも relation も返さず、`Data.define` の読み取り用の値（`Inventory::StockValue` など）に詰めて返す。AR モデルを返すと、受け取った側がそのモデルを書き換えられる。relation を返すと、受け取った側が `unscope`・`rewhere`・`update_all` で scope と書き込みの入口を越えられる。別のコンテキストの SQL に値を渡すときは `SqlSubquery` で返す（[graphql-schema.md「1 回のリクエストがたどる道」](../architecture/graphql-schema.md#1-回のリクエストがたどる道) 3）。全 spec の流れで戻り値を確かめるガード（`spec/support/public_api_returns.rb`）が、`app/public/` の公開の特異メソッドの戻り値を配列・Hash・`Set`・`Data` の項目・`OperationResult` の値までたどり、relation かモデルがあれば落とす。ほかの層との分担は「層ごとの責務」にある。
- **GraphQL の enum に写す一覧**：公開 API の値を GraphQL の enum に写すときは、その値を作るか受け付けるコードが読む一覧か、値を作る式との一致をそのパッケージの spec が確かめる一覧（状況の式と `ALL`）を、公開 API の定数として出す。`app/models/` の一覧は、同じオブジェクトを指す定数の別名でよい（`Purchasing::PurchaseOrders::STATUSES = PurchaseOrderStatus::ALL`）。別の配列に写した定数は、作る側に値を足しても変わらないので比べる相手にしない。`spec/graphql/enum_values_spec.rb` が、スキーマのすべての enum の型を、その定数と値の集合が等しいか、理由付きの比べない表に載るかのどちらかであることを確かめる。
- **引数**：操作者（`Partnerships::Actor`）を必須の引数にし、自パッケージの policy の scope（`Inventory::Scope` など）を掛けてから読む。

非公開のクラスを `app/public/` へ移すだけで違反を消すことは避ける。公開 API が抜け道として増えていくことは、プライバシーの検査を見直す条件である（ADR 002「見直す条件」）。

## つまずきやすい点

### 非公開のモデルのテストは、そのパッケージの spec/ に置く

リポジトリの直下の `spec/` はルートパッケージに属する。ルートはすべてのパッケージに依存してよいが、プライバシーの検査は掛かる。そのため、`spec/` に置いたテストが非公開のモデルを参照すると、packwerk が落とす。

```text
spec/zz_probe/sales_order_status_spec.rb:1:15
Privacy violation: '::Sales::SalesOrderStatus' is private to 'packs/sales' but referenced from '.'.
```

非公開のモデルを直接確かめるテストは、そのパッケージの `spec/` に置く（例：`packs/sales/spec/models/sales/sales_order_status_spec.rb`）。直下の `spec/` のテストは、公開 API と GraphQL を通して確かめ、レコードは `FactoryBot.create(:tenant)` のようにファクトリの名前で作る。ファクトリの名前はシンボルなので、packwerk の検査の対象にならない。

### GraphQL の型が参照するものは、公開 API に置く

GraphQL の層はルートパッケージにあるので、型やリゾルバが参照する定数は、すべて各パッケージの `app/public/` に置く。policy も同じで、`Types::ItemType` が `authorize_with Sales::ItemPolicy` と書くので、`Sales::ItemPolicy` は `packs/sales/app/public/` にある。

### 基底クラスはルートではなく platform に置く

各パッケージのモデルは `ApplicationRecord` を継承する。`ApplicationRecord` をルートパッケージに置くと、各パッケージがルートへの依存を宣言することになり、ルートは全パッケージに依存しているので循環になる。基底クラスや、全パッケージが使うテナントの仕組みは `packs/platform` に置く。

### 文字列で書いた定数は検査されない

packwerk は、ソースに定数として書かれた参照だけを見る。文字列から `constantize` で得たクラスは見えない。イベントの配送表 `Contracts::Subscriptions` は、受け手を `"Sales::PurchaseOrderTranslator"` のように文字列で書く。これで `contracts` は受け手のパッケージに依存せずに済む。代わりに、受け手の名前の誤りは packwerk ではなく、配送表のテスト（`spec/contracts/subscriptions_spec.rb`）が見つける。

### 名前空間とディレクトリを揃える

packs-rails の自動読み込みは Rails（Zeitwerk）の規則に従う。`packs/sales/app/models/sales/item.rb` は `Sales::Item` を定義しなければならない。ずれていると、手元の rspec では使うまで気づかず、CI と手元の E2E の Rails が起動の時に全コードを読み込むときに落ちる（[config.md「環境ごとの設定」](config.md#環境ごとの設定)の `test.rb` の `eager_load`）。
