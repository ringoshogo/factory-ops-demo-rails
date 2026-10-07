# GraphQL スキーマ

`context-map.md` の業務の流れを、GraphQL の API に落とす。実装者が型・リゾルバ・mutation を書くときと、レビュー担当が「発注側から相手の受注へたどれないこと」を確かめるときに読む。GraphQL の一般原則は `decisions.md` 6 章・7 章に従い、本書はそれを本デモに当てはめる。スキーマの形の判断は `../adr/004-GraphQLの型を視点ごとに分けnodeを置かない.md` に記録した。

ライブラリは graphql-ruby と Action Policy（`action_policy-graphql` を含む）を使う。Action Policy を Pundit より選ぶ理由は次の 2 つである。

- **1 つの policy に名前付きの scope を複数持てる**：出荷実績は、受注側には自社のものとして、発注側には経路 3 として見える。`relation_scope(:as_buyer)` のように、視点ごとの scope を同じ policy に並べられる。
- **認可の結果をリクエストの中でキャッシュできる**：型ごとの認可（「認可」）は、返すオブジェクトごとに評価される。取引関係の公開 API への問い合わせを、同じ相手については 1 回にできる。

## 1 回のリクエストがたどる道

フロントエンドから届いたクエリは、次の順に処理される。

1. **認証とテナントの設定**：ログインとログアウトは、GraphQL の外の `SessionsController` が受け持つ。GraphQL に認証の mutation は置かない。`SessionsController` は、認証専用の関数（`data-model.md`「RLS」）でユーザーと所有テナントを引き、両方の ID をセッションに保存する。`GraphqlController` は、リクエストごとにスキーマの実行全体を 1 つのトランザクションで包み、その先頭で `SET LOCAL app.tenant_id` にセッションのテナントを設定する。そのうえで RLS の下でユーザーを引き、`Current` に設定する。ユーザーが引けなければ、スキーマを実行せずに 401 を返す。`SET LOCAL` はトランザクションの中でしか効かないので、このトランザクションの外で発行したクエリは 0 行になる。トランザクションは、ユーザーエラーを返した場合も含め、実行が例外なく終わればコミットし、例外ならロールバックする。
   - API モードの Rails は Cookie・セッションのミドルウェアと CSRF 対策を持たない。ミドルウェアを明示的に足し、セッションの Cookie を `SameSite=Lax`・`HttpOnly` にする。`GraphqlController` と `SessionsController` は、`application/json` の本文だけを受け付ける（`ApplicationController`）。他サイトのフォームは `application/json` を送れず、`fetch` で送るには CORS のプリフライトが要るからである。`GraphqlController` は POST だけを受け付ける。
   - ログインは、成功したときにセッションを作り直してから ID を保存する。ログインの前のセッションを引き継がせないためである。
2. **視点の入口**：クエリは `buyer` か `supplier` のどちらかの入口から始まる（「視点ごとに型を分ける」）。
3. **公開 API の呼び出し**：リゾルバは、コンテキストの公開 API（`packs/*/app/public/`）を、操作者（`Partnerships::Actor`）を必須の引数にして呼ぶ。公開 API は、自コンテキストの policy の scope を掛けてから値を返す。
4. **型ごとの認可**：返った値を GraphQL の型に包むとき、型が宣言した policy の `show?` を評価する（「認可」）。
5. **入れ子のフィールド**：別のコンテキストの値が要るフィールドは、Dataloader でまとめて公開 API を呼ぶ（「ページングと N+1」）。

この道の上で、次の問いに答える必要がある。発注側と受注側の型をどう分けるか、相手側の型へたどれないことをどう保証するか、ID からレコードを引く入口をどう塞ぐか、認可の宣言漏れをどう止めるか。以下の節が順に答える。

## 視点ごとに型を分ける

ルートの `Query` には、視点ごとの入口を置く。各視点の読み取りは、この下にだけ置く。

```graphql
type Query {
  viewer: Viewer!
  "発注側の視点。購買が所有するデータと、相手テナントを読む 3 経路だけを持つ"
  buyer: BuyerView!
  "受注側の視点。受注・在庫・出荷・請求・取引関係が所有するデータを持つ"
  supplier: SupplierView!
}
```

実装者は、型を作るたびに、その型の視点を宣言する。

| 視点 | 意味 | 例 |
|---|---|---|
| `buyer` | 発注側の視点の型。購買が所有するデータと、相手テナントを読む 3 経路の型 | `PurchaseOrder`・`InboundShipment`・`ReceivedInvoice`・`SupplierShipment` |
| `supplier` | 受注側の視点の型。受注・在庫・出荷・請求・取引関係が所有するデータの型 | `SalesOrder`・`Item`・`PartMapping`・`Stock`・`Shipment`・`Invoice`・`Partnership` |
| `shared` | 視点を問わない葉の型。スカラーと enum と他の `shared` の型だけをフィールドに持つ | `Tenant`（ID と名前だけ）・`UserError`・`PageInfo` |
| `root` | ルートの型。視点の入口と `viewer`、または mutation を束ねる | `Query`・`Mutation` |

mutation の戻り値・コネクション・エッジの型は視点を宣言しない。mutation の戻り値の型は mutation の視点を、コネクションとエッジの型は中身の型の視点を、基底クラス（`Types::BasePayload`・`Types::BaseConnection`・`Types::BaseEdge`）が返す。

型の名前は、所有するコンテキストの言葉で付ける。同じ出荷実績でも、受注側の型は `Shipment`、発注側が経路 3 で見る型は `SupplierShipment`、購買が持つ写しの型は `InboundShipment` になる。

mutation は入れ子にせず、`Mutation` の直下に並べる。GraphQL は最上位の mutation だけを順に実行し、入れ子のフィールドは並行に解決するからである。視点は、mutation のクラスに宣言する。

### 相手側の型へたどれないことの保証

到達可能性のテスト（`spec/graphql/perspective_reachability_spec.rb`）が、CI で次の 3 つを確かめる。

1. `BuyerView` と、`buyer` を宣言した mutation の戻り値からたどれる型は、すべて `buyer` か `shared` である。`SupplierView` 側も同様に確かめる。
2. `shared` の型のフィールドは、スカラー・enum・`shared` の型だけを返す。
3. `buyer` の型のうち、相手テナントのデータを返す型は、`PublishedCatalogItem`・`SupplierPartnership`・`SupplierShipment` の 3 つに限られる。各型は、対応する読む経路を宣言する（`cross_tenant_read :catalog`・`:partnerships`・`:shipments`）。

発注の型に受注へのフィールドを 1 本足すと、1 が落ちる。相手側の型を 4 つ目として足すと、3 が落ちる。

## 発注側の視点

発注側の型が持つのは、購買が所有するデータと、相手テナントを読む 3 つの経路だけである（`context-map.md`「テナントと所有」）。

| 経路 | 型 | 開く条件 | 呼ぶ公開 API |
|---|---|---|---|
| 1. カタログ | `SupplierPartnership.catalog` → `PublishedCatalogItem` | 有効な取引関係と `view_catalog` の付与 | `Sales::PublishedCatalog` |
| 2. 取引関係 | `BuyerView.suppliers` → `SupplierPartnership` | 有効な取引関係 | `Partnerships::Directory` |
| 3. 自社の発注に連結した出荷 | `PurchaseOrder.supplierShipments` → `SupplierShipment` | 有効な取引関係と `view_shipments` の付与 | `Fulfillment::PartnerShipments` |

開く条件は、各公開 API が取引関係の公開 API（`Partnerships::Access`）に問い合わせて判定する。条件を満たさなければ、公開 API は空を返す。GraphQL 層では、経路ごとにエラーにも `null` にもしない。取引関係が失効した時点で、3 つの経路はどれも空になり、RLS も同じ行を閉じる（`data-model.md`「RLS」）。

経路 3 の出荷実績は、購買が持つ写しの入荷（`InboundShipment`）と同じ出荷を指す。業務の正本は写しの入荷で、検収はこれに対して行う。経路 3 は、受注側の出荷実績そのものを、権限付与がある間だけ見せる。

相手側の型は、相手テナントの内部の ID を持たない。`PublishedCatalogItem` は品目 ID を、`SupplierPartnership` は取引関係 ID を、`SupplierShipment` は出荷実績 ID を返さない。それぞれ品目コード、受注側テナント、連結先の発注で識別する。購買が持つ相手側の ID（`data-model.md`「購買」）も、GraphQL のフィールドには出さない。

```graphql
type BuyerView {
  suppliers: [SupplierPartnership!]!
  purchaseOrders(first: Int, after: String, filter: PurchaseOrderFilter): PurchaseOrderConnection!
  purchaseOrder(id: ID!): PurchaseOrder
  receivedInvoices(first: Int, after: String): ReceivedInvoiceConnection!
  receivedInvoice(id: ID!): ReceivedInvoice
}

"経路 2。自社が発注側である有効な取引関係。相手との関係は受注側テナントで識別する"
type SupplierPartnership {
  supplier: Tenant!
  permissions: [PartnershipPermission!]!
  "経路 1。view_catalog が無ければ空"
  catalog(first: Int, after: String): PublishedCatalogItemConnection!
}

type PublishedCatalogItem {
  code: String!
  name: String!
  unit: String!
  unitPrice: BigInt!
  taxRatePercent: Int!
}

type PurchaseOrder {
  id: ID!
  orderNo: String!
  supplier: Tenant!
  orderDate: ISO8601Date!
  desiredDeliveryOn: ISO8601Date
  status: PurchaseOrderStatus!
  "回答待ちの取消依頼がある"
  cancellationPending: Boolean!
  lines: [PurchaseOrderLine!]!
  cancellationRequests: [CancellationRequest!]!
  inboundShipments: [InboundShipment!]!
  "経路 3。view_shipments が無ければ空"
  supplierShipments: [SupplierShipment!]!
}

type PurchaseOrderLine {
  id: ID!
  partNumber: String!
  quantity: Int!
  "受注確定で写した値。確定前は空"
  confirmedItemName: String
  confirmedUnitPrice: BigInt
}

type CancellationRequest {
  id: ID!
  reason: String!
  outcome: CancellationOutcome
  decidedAt: ISO8601DateTime
}

"出荷計上の写し"
type InboundShipment {
  id: ID!
  shippedOn: ISO8601Date!
  lines: [InboundShipmentLine!]!
  inspection: ReceiptInspection
}

type InboundShipmentLine {
  id: ID!
  purchaseOrderLine: PurchaseOrderLine!
  shippedQuantity: Int!
  "検収前は空"
  acceptedQuantity: Int
}

type ReceiptInspection {
  inspectedOn: ISO8601Date!
}

type SupplierShipment {
  shippedOn: ISO8601Date!
  lines: [SupplierShipmentLine!]!
}

type SupplierShipmentLine {
  purchaseOrderLine: PurchaseOrderLine!
  quantity: Int!
}

"請求書発行の写し"
type ReceivedInvoice {
  id: ID!
  invoiceNumber: String!
  supplier: Tenant!
  periodStart: ISO8601Date!
  periodEnd: ISO8601Date!
  issuedOn: ISO8601Date!
  subtotal: BigInt!
  taxTotal: BigInt!
  total: BigInt!
  lines: [ReceivedInvoiceLine!]!
}

type ReceivedInvoiceLine {
  purchaseOrderLine: PurchaseOrderLine!
  itemName: String!
  unitPrice: BigInt!
  quantity: Int!
  taxRatePercent: Int!
  amount: BigInt!
}
```

`SupplierShipmentLine.purchaseOrderLine` は、出荷明細が持つ発注明細 ID の写しから、購買の公開 API で自社の発注明細を引く。受注明細や出荷依頼を経由しない。

## 受注側の視点

受注側の型は、自社が所有するデータだけを返す。発注側の発注・検収・受領請求書へのフィールドは無い。受注の連結元の発注 ID（`sales_orders.source_purchase_order_id`）など、相手側を指す ID 列もフィールドに出さない。

以下の SDL は抜粋である。省いた型（`ShipmentRequestLine`・`ShippingInstruction`・`BillableItem`・`InvoiceTaxSummary` など）は、`data-model.md` の表の列のうち、相手側を指す ID 列を除いたものをフィールドにする。

同じテナントの中で複数のコンテキストを束ねるフィールド（受注 → 出荷依頼、出荷依頼明細 → 受注明細）は、ルートパッケージで両方の公開 API を呼んで解決する。コンテキスト同士は依存しない（`context-map.md`「疎結合を守る規則」5）。

```graphql
type SupplierView {
  partnerships: [Partnership!]!
  items(first: Int, after: String): ItemConnection!
  partMappings(customerTenantId: ID, first: Int, after: String): PartMappingConnection!
  salesOrders(first: Int, after: String, filter: SalesOrderFilter): SalesOrderConnection!
  salesOrder(id: ID!): SalesOrder
  stocks(first: Int, after: String, filter: StockFilter): StockConnection!
  stockMovements(itemId: ID, first: Int, after: String): StockMovementConnection!
  shipmentRequests(first: Int, after: String, filter: ShipmentRequestFilter): ShipmentRequestConnection!
  billingTerms: [BillingTerm!]!
  "未請求の請求対象明細"
  billableItems(customerTenantId: ID, first: Int, after: String): BillableItemConnection!
  invoices(first: Int, after: String, filter: InvoiceFilter): InvoiceConnection!
  invoice(id: ID!): Invoice
  dashboard: SupplierDashboard!
}

type Partnership {
  id: ID!
  buyer: Tenant!
  status: PartnershipStatus!
  revokedAt: ISO8601DateTime
  permissions: [PartnershipPermission!]!
}

type SalesOrder {
  id: ID!
  orderNo: String!
  customer: Tenant!
  orderDate: ISO8601Date!
  dueDate: ISO8601Date
  status: SalesOrderStatus!
  "未決の取消の審査がある"
  cancellationReviewPending: Boolean!
  lines: [SalesOrderLine!]!
  cancellationReviews: [CancellationReview!]!
  "全量引当で出荷可能になった後に現れる"
  shipmentRequest: ShipmentRequest
}

type SalesOrderLine {
  id: ID!
  customerPartNumber: String!
  "照合前は空"
  item: Item
  itemName: String
  unitPrice: BigInt
  taxRatePercent: Int
  quantity: Int!
  allocatedQuantity: Int!
}

type Item {
  id: ID!
  code: String!
  name: String!
  unit: String!
  unitPrice: BigInt!
  taxRatePercent: Int!
  published: Boolean!
  stock: Stock
}

type PartMapping {
  id: ID!
  customer: Tenant!
  customerPartNumber: String!
  item: Item!
}

type CancellationReview {
  id: ID!
  requestedAt: ISO8601DateTime!
  decision: CancellationOutcome
  decidedAt: ISO8601DateTime
}

type Stock {
  item: Item!
  onHand: Int!
  allocated: Int!
  available: Int!
  safetyStock: Int!
  belowSafetyStock: Boolean!
}

type ShipmentRequest {
  id: ID!
  salesOrder: SalesOrder!
  customer: Tenant!
  dueDate: ISO8601Date
  status: ShipmentRequestStatus!
  lines: [ShipmentRequestLine!]!
  instruction: ShippingInstruction
  shipment: Shipment
}

type Shipment {
  id: ID!
  shippedOn: ISO8601Date!
  lines: [ShipmentLine!]!
}

type Invoice {
  id: ID!
  invoiceNumber: String!
  customer: Tenant!
  periodStart: ISO8601Date!
  periodEnd: ISO8601Date!
  state: InvoiceState!
  issuedAt: ISO8601DateTime
  subtotal: BigInt!
  taxTotal: BigInt!
  total: BigInt!
  taxSummaries: [InvoiceTaxSummary!]!
  items(first: Int, after: String): BillableItemConnection!
}

"葉の型。どちらの視点からも、ID と名前だけを見せる"
type Tenant {
  id: ID!
  name: String!
}
```

金額は `BigInt`（graphql-ruby の `GraphQL::Types::BigInt`。文字列で運ぶ）にする。GraphQL の `Int` は 32 ビットで、月次の請求金額があふれうるからである。数量は `Int` にする。

## ID と `node`

ID は、主キーの UUIDv7 をそのまま `ID` 型で返す。型名を埋め込んだグローバル ID は作らない。

汎用の `node(id:)`・`nodes(ids:)` は置かない。相手テナントは、イベントで渡った出荷実績 ID・請求書 ID を持っているので、型を問わない入口は相手のデータへ届く穴になる（`../adr/004-GraphQLの型を視点ごとに分けnodeを置かない.md`）。スキーマの `object_from_id` は実装せず、呼ばれたら例外にする。これで、graphql-ruby の `node` フィールドと、引数の `loads:`（ID から自動でオブジェクトを読み込む機能）の両方が使えなくなる。

ID でレコードを引く入口は、視点の下に型ごとに置く（`buyer.purchaseOrder(id:)`・`supplier.salesOrder(id:)` など）。mutation も ID を引数で受け取り、公開 API に操作者と一緒に渡す。どちらも公開 API の scope を通るので、見えない ID は存在しない ID と同じ扱いになる。クエリでは `null` を返し、mutation ではユーザーエラー `NOT_FOUND` を返す。存在するが見えない、という区別を返さない。

相手テナントを指す引数も、テナントが存在するかどうかを明かさない。

- **取引関係を前提にする引数**（`placePurchaseOrder` の `supplierTenantId` など）：公開 API はテナントを引かず、`Partnerships::Access` の判定だけで扱う。存在しないテナントも、取引関係の無いテナント・失効したテナント・権限付与の無いテナントと同じ `NOT_PERMITTED` になる。
- **取引関係を結ぶ相手**（`establishPartnership`）：受注側の `admin` は、相手を発注側テナントの取引用コード（`tenants.partner_code`）で指定する。取引用コードは推測できない無作為の値で、発注側の `admin` が `viewer.partnerCode` で読み、受注側へ業務の外で伝える。一致するテナントが無ければ `NOT_FOUND` を返す。相手の名前は、取引関係を結んだ後に `Partnership.buyer` で初めて見せる。テナントの `code` は推測できるので、指定に使わない。使うと、総当たりで他社の名前を集められる。

## 認可：宣言の無い型・リゾルバ・mutation は拒否する

認可の判定は 2 か所に分かれる。

- **可視範囲（scope）**：各コンテキストの policy の `relation_scope` に置く。コンテキストの公開 API は、操作者を必須の引数に取り、内部で scope を掛けてから値を返す。操作者を渡さずにレコードを返す公開 API は作らない。scope は所有の条件を明示し、RLS に任せない。自社のデータを返す scope は `owner_tenant_id` が操作者のテナントであることを、経路 3 の scope は `buyer_tenant_id` が操作者のテナントであることと権限付与を条件にする。RLS は経路 1〜3 の相手の行も返すので、RLS に任せると、受注側の一覧や ID 指定の入口に相手の公開品目・取引関係・出荷が自社の物として混ざる。型の `show?` も同じ条件で判定する。
- **型・入口・操作ごとの規則**：GraphQL の基底クラスが、宣言された policy の規則を評価する。

policy は、コンテキストの公開 API として `packs/<パッケージ>/app/public/<名前空間>/` に置く。GraphQL 層は、公開 API が返す値に対して同じ policy の規則を評価する。scope と規則が同じ policy クラスにあるので、可視範囲の定義は 1 か所に保たれる（`decisions.md` 2 章「可視範囲」）。

業務の不変条件は、policy ではなく公開 API の中で確かめる。発注の登録時の `place_orders` の問い合わせ、出荷済みの受注の取消の拒否などがこれに当たり、違反はユーザーエラーとして返す（「エラー」）。

### 基底クラス

実装者は、型・リゾルバ・mutation を必ず次の基底クラスから作り、宣言を書く。宣言が無ければ、実行時に拒否する。

| 基底クラス | 必須の宣言 | 実行時の動き |
|---|---|---|
| `Types::BaseObject` | `perspective`（視点）と、`authorize_with <Policy>` か `authorization_exempt reason:` のどちらか | graphql-ruby の `authorized?` で、返すオブジェクトごとに policy の `show?` を評価する。宣言が無ければ拒否する |
| `Resolvers::BaseResolver` | `perspective` と `authorize_with <Policy>, :<規則>` | 解決の前に規則を評価する。`buyer`・`supplier` の入口の下のフィールドは、すべてリゾルバで書く |
| `Mutations::BaseMutation` | `perspective` と `authorize_with <Policy>, :<規則>` | 対象の値を公開 API で引いた後、公開 API の操作を呼ぶ前に規則を評価する。対象が無い作成系は、操作者に対して評価する |

policy は `ApplicationPolicy`（`packs/platform`）を継承し、規則の `user` で操作者（`Partnerships::Actor`）を受け取る。`GraphqlController` は、操作者を GraphQL の `context[:current_user]` に入れて渡す。

mutation の実装者は、公開 API の操作を呼ぶ `perform` を書く。対象を引く mutation は、公開 API で対象を引く `find_target` も書く。基底 mutation は、`find_target` が `nil` を返せば `NOT_FOUND` のユーザーエラーを返し、引けた対象に規則を評価してから `perform` を呼ぶ。`find_target` の無い mutation は、操作者に規則を評価してから `perform` を呼ぶ。成功したときの値を返すフィールドは `result_field` で宣言する。

宣言の無いクラスは、開発環境とテストでは例外で落ちる。本番では拒否したうえで、エラー通知に送る。

scope を通った値が型の `show?` で拒否されることは、通常は起きない。起きた場合は、scope と規則の食い違いか、リゾルバが別の値を混ぜた不具合である。そのフィールドは `null` にし、トップレベルのエラー `FORBIDDEN` を返し、エラー通知に送る。

拒否をどこで起きても `FORBIDDEN` に揃えるため、実装者は次の 2 か所を書く。graphql-ruby は、`authorized?` が偽を返すと値を `null` に置き換えるだけで、エラーを出さないからである。

- **型とフィールド**：スキーマのクラス（`GraphQL::Schema` を継承したもの）で `self.unauthorized_object` と `self.unauthorized_field` を上書きする。どちらも、`extensions: { "code" => "FORBIDDEN" }` を持つ `GraphQL::ExecutionError` を投げ、エラー通知に送る。
- **リゾルバと mutation**：`Resolvers::BaseResolver` と `Mutations::BaseMutation` の `authorized?` は、偽を返さず、同じエラーを投げる。

### 明示的な例外と列挙テスト

`authorization_exempt` は、データを持たないか、認可済みの型の中でだけ現れる型に限る。列挙テスト（`spec/graphql/authorization_declarations_spec.rb`）が、スキーマの全型・全リゾルバ・全 mutation を走査し、宣言があることと、例外の一覧が次の表と一致することを確かめる（`decisions.md` 7 章）。

| 例外の型 | 理由 |
|---|---|
| `Query`・`Mutation` | ルートの型。`Query` は `viewer` と視点の入口だけを、`Mutation` は mutation だけを持ち、各 mutation が宣言する |
| `Viewer` | ログイン中のユーザーと自社テナントだけを返す |
| `BuyerView`・`SupplierView` | データを持たない入口。フィールドはすべてリゾルバで、各自が宣言する |
| `Tenant` | ID と名前だけの葉。認可済みの型のフィールドとしてだけ現れる |
| `UserError`・`PageInfo` | データを持たない |
| 各 mutation の戻り値の型 | 中身の型が、それぞれ宣言を持つ |
| 各コネクションとエッジの型 | 中身の型が、それぞれ宣言を持つ |

例外を足すときは、この表と列挙テストの期待値を同じ変更で足す。

列挙テストは、スキーマの型が object・スカラー・enum・input だけであることも確かめる。interface と union は、異なる視点の型を 1 つのフィールドにまとめられるので、到達可能性のテストと列挙テストに検査を足すまで使わない。

### 役割による制限

取引関係と権限付与を変える mutation は、`admin` のユーザーに限る。policy の規則（`Partnerships::PartnershipPolicy#manage?`）で判定し、拒否は `FORBIDDEN` で返す。それ以外の操作は、自社のユーザーなら役割を問わない。

## 読み取りの一覧

各リゾルバが呼ぶ公開 API を示す。GraphQL 層が呼ぶ公開 API の名前は本書で決める。コンテキスト同士が呼ぶ公開 API（`Inventory::Allocation` など）は `context-map.md` が定める。

**発注側**

| フィールド | 呼ぶ公開 API |
|---|---|
| `buyer.suppliers` | `Partnerships::Directory.for_buyer` |
| `SupplierPartnership.catalog` | `Sales::PublishedCatalog.items` |
| `buyer.purchaseOrders`・`buyer.purchaseOrder` | `Purchasing::PurchaseOrders` |
| `PurchaseOrder.lines`・`cancellationRequests`・`inboundShipments` | `Purchasing::PurchaseOrders`（発注 ID をまとめて渡す） |
| `PurchaseOrder.supplierShipments` | `Fulfillment::PartnerShipments.for_purchase_orders` |
| `buyer.receivedInvoices`・`buyer.receivedInvoice` | `Purchasing::ReceivedInvoices` |
| `PurchaseOrder.supplier`・`ReceivedInvoice.supplier` | `Partnerships::Directory.tenants` |

**受注側**

| フィールド | 呼ぶ公開 API |
|---|---|
| `supplier.partnerships` | `Partnerships::Directory.for_supplier` |
| `supplier.items`・`Item` | `Sales::Catalog` |
| `supplier.partMappings` | `Sales::PartMappings` |
| `supplier.salesOrders`・`supplier.salesOrder` | `Sales::SalesOrders`（状況と引当数量は、受注の公開 API が在庫の `Inventory::Allocation` から得て返す） |
| `SalesOrder.shipmentRequest` | `Fulfillment::ShipmentRequests.for_sales_orders` |
| `supplier.stocks`・`Item.stock`・`supplier.stockMovements` | `Inventory::Stocks` |
| `supplier.shipmentRequests`・`ShipmentRequest.instruction`・`shipment` | `Fulfillment::ShipmentRequests` |
| `ShipmentRequest.salesOrder`・`ShipmentRequestLine.salesOrderLine` | `Sales::SalesOrders` |
| `supplier.billingTerms` | `Billing::Terms` |
| `supplier.billableItems`・`Invoice.items` | `Billing::BillableItems` |
| `supplier.invoices`・`supplier.invoice` | `Billing::Invoices` |
| `supplier.dashboard` | `Sales::SalesOrders.count_by_status`・`Inventory::Stocks.below_safety_stock`・`Fulfillment::ShipmentRequests.due_within`・`Billing::BillableItems.unbilled_total` |

ダッシュボードは、factory-ops-demo の画面と同じく、複数のコンテキストの集計を 1 つの型に束ねる読み取り専用のクエリである。

## mutation の一覧

各 mutation が呼ぶ公開 API と、その操作が同じトランザクションで出すイベントを示す。イベントを出すのは公開 API の中で、GraphQL 層はイベントを出さない。公開 API は、イベントのジョブをリクエストのトランザクションの中で登録する。ジョブはコミットまでワーカーから見えず、リクエストが戻ればジョブも消える（`../adr/005-イベントのジョブをトランザクション内で登録する.md`）。

**発注側**

| mutation | 呼ぶ公開 API | 出すイベント |
|---|---|---|
| `placePurchaseOrder` | `Purchasing::Ordering.place`（`Partnerships::Access` で `place_orders` を確かめる） | 発注登録 |
| `requestPurchaseOrderCancellation` | `Purchasing::Ordering.request_cancellation` | 取消依頼 |
| `inspectInboundShipment` | `Purchasing::ReceiptInspection.record` | 検収完了 |

**受注側**

| mutation | 呼ぶ公開 API | 出すイベント |
|---|---|---|
| `saveItem`・`setItemPublished` | `Sales::Catalog` | なし |
| `registerPartMapping` | `Sales::PartMappings.register`（照合待ちの受注を照合し直す） | 全明細が照合できた受注ごとに受注確定 |
| `allocateSalesOrder` | `Sales::OrderAllocation.allocate`（`Inventory::Allocation` を同期で呼ぶ） | 全量引当になったら出荷可能 |
| `cancelSalesOrder` | `Sales::OrderCancellation.cancel`（引当を解除する） | 受注取消・出荷取消 |
| `approveCancellationReview` | `Sales::CancellationReviews.approve`（引当を解除する） | 取消承認・出荷取消 |
| `rejectCancellationReview` | `Sales::CancellationReviews.reject` | 取消却下・出荷停止解除 |
| `createShippingInstruction`・`cancelShippingInstruction` | `Fulfillment::Instructions` | なし |
| `postShipment` | `Fulfillment::Shipping.post`（`Inventory::Allocation` で引当を消費する） | 出荷計上 |
| `adjustStock` | `Inventory::Adjustment`（入庫・出庫） | なし |
| `setBillingTerm` | `Billing::Terms.set` | なし |
| `closeBillingPeriod` | `Billing::Closing.close`（下書きの請求書を作る） | なし |
| `discardDraftInvoice` | `Billing::Closing.discard` | なし |
| `issueInvoice` | `Billing::Closing.issue` | 請求書発行 |
| `establishPartnership` | `Partnerships::Management.establish`（相手は発注側テナントの取引用コードで指定する。「ID と `node`」） | なし |
| `revokePartnership` | `Partnerships::Management.revoke` | なし |
| `grantPermission`・`withdrawPermission` | `Partnerships::Management` | なし |

受注側の ACL がイベントを受けて出すイベントは、上の表に載らない。ACL は、「発注登録」を受けて「受注確定」か「品番照合待ち」を、「取消依頼」を受けて「出荷停止」を（受注が出荷済みなら「取消却下」を）、「検収完了」を受けて「請求対象確定」を出す。取引関係の失効はイベントを出さない。失効の効果は、各公開 API が `Partnerships::Access` に問い合わせた時点で現れる（`context-map.md`「取引関係の失効」）。

mutation の引数と戻り値は、次の形に揃える。

```graphql
type Mutation {
  placePurchaseOrder(input: PlacePurchaseOrderInput!): PlacePurchaseOrderPayload!
  # 以下、上の表の mutation が同じ形で並ぶ
}

input PlacePurchaseOrderInput {
  supplierTenantId: ID!
  desiredDeliveryOn: ISO8601Date
  lines: [PurchaseOrderLineInput!]!
}

input PurchaseOrderLineInput {
  partNumber: String!
  quantity: Int!
}

type PlacePurchaseOrderPayload {
  "失敗したときは空"
  purchaseOrder: PurchaseOrder
  errors: [UserError!]!
}
```

## 状況の enum

発注と受注の状況は、`data-model.md`「状態は保存せず、時刻列から導出する」の表と同じ優先順で、公開 API が導出して返す。GraphQL 層は導出しない。取消の依頼中・審査中は状況に重ねて示すので、enum の値にせず、別の真偽値のフィールドにする。

| enum | 値（導出表の状況） | 重ねて示すフィールド |
|---|---|---|
| `PurchaseOrderStatus` | `SUPPLIER_CANCELLED`（受注側により取消）・`CANCELLED`（取消済み）・`INSPECTED`（検収済）・`INBOUND`（入荷予定）・`ACCEPTED`（受注済）・`AWAITING_SUPPLIER_CONFIRMATION`（受注側で確認中）・`SENT`（送信済み） | `PurchaseOrder.cancellationPending`（取消依頼中） |
| `SalesOrderStatus` | `CANCELLED`（取消済）・`INSPECTED`（検収済）・`SHIPPED`（出荷済）・`AWAITING_PART_MATCH`（品番照合待ち）・`ALLOCATED`（引当済）・`PARTIALLY_ALLOCATED`（一部引当）・`RECEIVED`（受注済） | `SalesOrder.cancellationReviewPending`（取消審査中） |
| `ShipmentRequestStatus` | `CANCELLED`（取消済）・`SHIPPED`（出荷済）・`ON_HOLD`（出荷停止中）・`INSTRUCTED`（出荷指示済）・`READY`（出荷待ち） | — |

その他の enum は、保存された列の値をそのまま写す。

| enum | 値 | 元の列 |
|---|---|---|
| `PartnershipStatus` | `ACTIVE`・`REVOKED` | `partnerships.status` |
| `PartnershipPermission` | `VIEW_CATALOG`・`PLACE_ORDERS`・`VIEW_SHIPMENTS` | `partnership_grants.permission` |
| `CancellationOutcome` | `APPROVED`・`REJECTED`（空は回答待ち・審査中） | `cancellation_requests.outcome`・`cancellation_reviews.decision` |
| `InvoiceState` | `DRAFT`・`ISSUED` | `invoices.issued_at` の有無 |
| `StockMovementType` | `INBOUND`・`OUTBOUND`・`ALLOCATE`・`DEALLOCATE`・`SHIP` | `stock_movements.type` |

## エラー

エラーは、利用者が直せるかどうかで 2 つに分ける。

| 種類 | 返し方 | 例 |
|---|---|---|
| ユーザーエラー | mutation の戻り値の `errors`。HTTP は 200 | 入力の誤り、業務の不変条件の違反、見えない ID、取引関係の無い相手 |
| トップレベルのエラー | GraphQL の `errors`。`extensions.code` に種別を入れる | 認証切れ、規則による拒否・宣言漏れ・scope と規則の食い違い（`FORBIDDEN`）、クエリの上限超過、想定外の例外 |

```graphql
type UserError {
  code: UserErrorCode!
  message: String!
  "入力のどこが原因か。入力全体なら空"
  path: [String!]
}

enum UserErrorCode {
  INVALID_INPUT   # 形式や範囲の誤り（検収数量が出荷数量を超える など）
  NOT_FOUND       # 存在しないか、見えない ID
  NOT_PERMITTED   # 権限付与が無い、取引関係が無いか失効している（存在しない相手テナントを含む）
  CONFLICT        # 状態と両立しない（出荷済みの受注の取消、回答待ちの取消依頼の重複 など）
}
```

公開 API の操作は、成功なら値、失敗ならエラーコードと対象の入力項目を持つ結果の値（`OperationResult`、`packs/platform`）を返す。基底 mutation が、それを `UserError` に写す。入力項目は `[:lines, 0, :unit_price]` のように公開 API の名前で返し、基底 mutation が `path` の GraphQL の名前（`["lines", "0", "unitPrice"]`）に直す。公開 API の操作は、業務の不変条件の違反で例外を投げない。失敗を返す操作は、書き込みを `transaction(requires_new: true)` の中で行い、失敗を返す前にそのセーブポイントまで戻す。操作はリクエスト全体のトランザクションの中で動くので、入れ子の `transaction` で `ActiveRecord::Rollback` を投げても書き込みは戻らず、リクエストの終わりにコミットされる。セーブポイントまで戻すと、その中で登録したイベントのジョブも一緒に戻る。

## ページングと N+1

一覧は Relay のコネクション（`first`・`after`）で返す。カーソルは主キーの UUIDv7 で、作成順の新しいものから並べる。公開 API は、操作者・件数・カーソルを受け取り、1 ページ分の値と次のカーソルを返す。GraphQL 層は、それをコネクションに包む。件数の総数（`totalCount`）は返さない。

明細・権限付与・取引関係・請求条件のように、親ごとの件数が小さい集まりは、コネクションにせずリストで返す。

別のコンテキストの値や子の値を引くフィールドは、`GraphQL::Dataloader` のソースを通して公開 API を呼ぶ。公開 API は、そのために ID の配列を受け取る一括取得のメソッドを持つ（例：`Sales::SalesOrders.lines_for(order_ids)`）。1 件ずつ引くメソッドを、入れ子のフィールドから呼ばない。ソースは操作者を引数に取り、公開 API にそのまま渡す。

Dataloader のソースは、リクエストのトランザクションと同じ DB 接続で動かす。graphql-ruby の Dataloader はソースを別の Fiber で実行するので、`config.active_support.isolation_level` を既定の `:thread` のままにし、`GraphQL::Dataloader::AsyncDataloader` は使わない。`:fiber` にすると Fiber ごとに別の接続を取り、`SET LOCAL` の無い接続で引いたソースが例外ではなく 0 行を返す。

クエリには次の上限を設ける（`decisions.md` 6 章）。複雑度の上限は、1 ページの一覧を画面に必要なフィールドで取る問い合わせが通り、コネクションを入れ子にして件数が掛け算になる問い合わせが通らない値にする。graphql-ruby は、コネクションの中のフィールドの複雑度を、1 ページの最大件数倍で数える。リストで返す明細は掛け算にならない。

| 上限 | 値 | 決め方 |
|---|---|---|
| 深さ（`max_depth`） | 10 | 視点の入口から明細の葉までが収まる |
| 1 ページの件数の既定（`default_page_size`） | 20 | `first` を省いた一覧が、上限まで膨らまない |
| 1 ページの件数の上限（`default_max_page_size`） | 100 | — |
| 複雑度（`max_complexity`） | 2,500 | 100 件の一覧で各行が 20 前後のフィールドを取ると 2,000 前後になり、通る。100 件の一覧の中に 100 件のコネクションを入れ子にすると 10,000 を超え、通らない |

実装者は、画面の問い合わせを足すたびに、その複雑度を graphql-ruby の複雑度の解析で計るテストを書き、上限に収まることを確かめる。
