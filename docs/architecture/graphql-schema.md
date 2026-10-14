# GraphQL スキーマ

`context-map.md` の業務の流れを、GraphQL の API に落とす。実装者が型・リゾルバ・mutation を書くときと、レビュー担当が「発注側から相手の受注へたどれないこと」を確かめるときに読む。GraphQL の一般原則は `decisions.md` 6 章・7 章に従い、本書はそれを本デモに当てはめる。スキーマの形の判断は `../adr/004-GraphQLの型を視点ごとに分けnodeを置かない.md` に記録した。

ライブラリは graphql-ruby と Action Policy（`action_policy-graphql` を含む）を使う。Action Policy を Pundit より選ぶ理由は次の 2 つである。

- **1 つの policy に名前付きの scope を複数持てる**：出荷実績は、受注側には自社のものとして、発注側には経路 3 として見える。`relation_scope(:as_buyer)` のように、視点ごとの scope を同じ policy に並べられる。
- **認可の結果をリクエストの中でキャッシュできる**：型ごとの認可（「認可」）は、返すオブジェクトごとに評価される。取引関係の公開 API への問い合わせを、同じ相手については 1 回にできる。

認可は、DB の RLS、Action Policy の scope、Action Policy の操作ごとの規則の 3 段で分担する。自社のデータか相手のデータかで仕組みを使い分けるのではなく、どのデータにも 3 段が順に掛かる。各段が何を決めるかは「認可：宣言の無い型・リゾルバ・mutation は拒否する」の表にある。

## 1 回のリクエストがたどる道

フロントエンドから届いたクエリは、次の順に処理される。

1. **認証とテナントの設定**：ログインとログアウトは、GraphQL の外の `SessionsController` が受け持つ。GraphQL に認証の mutation は置かない。`SessionsController` は、認証専用の関数（`data-model.md`「RLS」）でユーザーと所有テナントを引き、両方の ID とユーザーのセッションの世代をセッションに保存する。`GraphqlController` は、リクエストごとにスキーマの実行全体を 1 つのトランザクションで包み、その先頭で `SET LOCAL app.tenant_id` にセッションのテナントを設定する。そのうえで RLS の下でユーザーを引き、`Current` に設定する。ユーザーが引けないか、セッションの世代がユーザーの今の世代と違えば、スキーマを実行せずに 401 を返す。`SET LOCAL` はトランザクションの中でしか効かないので、このトランザクションの外で発行したクエリは 0 行になる。トランザクションは、実行が例外なく終わり、結果にトップレベルのエラーが無ければコミットする。ユーザーエラーだけを返した場合もコミットする。例外か、トップレベルのエラー（`FORBIDDEN`、クエリの検証や上限の違反など）ならロールバックする。graphql-ruby は `GraphQL::ExecutionError` を拾って `errors` に載せるので、例外だけを見ると、書き込みの後に `FORBIDDEN` になった操作がコミットされる。
   - API モードの Rails は Cookie・セッションのミドルウェアと CSRF 対策を持たない。ミドルウェアを明示的に足し、セッションの Cookie を `SameSite=Lax`・`HttpOnly` にする。`GraphqlController` と `SessionsController` は、`application/json` の本文だけを受け付ける（`ApplicationController`）。他サイトのフォームは `application/json` を送れず、`fetch` で送るには CORS のプリフライトが要るからである。`GraphqlController` は POST だけを受け付ける。
   - ログインは、成功したときにセッションを作り直してから ID を保存する。ログインの前のセッションを引き継がせないためである。
   - `GraphqlController` は、スキーマを実行する前に、ログの文脈（リクエスト ID・テナント・ユーザー・操作名・相関 ID）を `Rails.event.set_context` で設定する。文脈は Fiber のストレージにあり、Dataloader の Fiber は作られた時点の値を写して持つので、実行の途中で設定した値はフィールドの解決に届かない（`../implementation-plan.md` M18）。
   - セッションは Cookie に置き、サーバーに残さない。そのため、セッションを消しても、写した Cookie を送り直せば使えてしまう。これを防ぐため、ユーザーごとにセッションの世代（`users.session_version`、`data-model.md`「取引関係と権限付与（`partnerships`）」）を持たせ、ログアウトとパスワードの変更で世代を進める。パスワードの変更では DB のトリガーが進めるので、書き換える経路を問わない。ログアウトは、世代が今と同じセッションのときだけ進める。無効になった Cookie で、他の端末のログインを切らせないためである。公開の配置（`deploy/`）では、全員がログインの画面に並ぶ同じアカウントを使うので、`web` に `SHARED_DEMO_ACCOUNTS=1` を渡し、ログアウトで世代を進めず Cookie を消すだけにする。世代を進めると、同じアカウントのほかの訪問者が全員切れるからである。このとき、ログアウトの前に写し取られた Cookie は期限まで使えるままになる。公開の配置では資格情報がログインの画面に出ているので、この保証を外す。セッションの期限は、最後のリクエストから 12 時間とする（`config/application.rb` の `expire_after`）。Rails は応答のたびに期限を延ばした Cookie を書き直すが、画面（`frontend/`）では、Next がブラウザへ Cookie を写せるのは server action と route handler の応答だけで、サーバーコンポーネントの読み取りの応答では写せない。そのため画面の利用者の期限は、ログインか最後の書き込みから 12 時間になる（`frontend/lib/graphql/request.ts`）。
2. **視点の入口**：クエリは `buyer` か `supplier` のどちらかの入口から始まる（「視点ごとに型を分ける」）。
3. **公開 API の呼び出し**：リゾルバは、コンテキストの公開 API（`packs/*/app/public/`）を、操作者（`Partnerships::Actor`）を必須の引数にして呼ぶ。公開 API は、自コンテキストの policy の scope を掛けてから値を返す。別のコンテキストの値を SQL の中で読む公開 API（受注の状況が読む在庫の引当数量）には、相手の公開 API が、scope を掛けた後に SQL の文字列にした副問い合わせを、列の名前と一緒に値（`SqlSubquery`、`packs/platform`）で返す。受け取る側は条件を足さずに副問い合わせとして結ぶだけで、相手の relation もモデルも受け取らない。relation を受け取ると、`unscope`・`rewhere`・`update_all` で相手の scope と書き込みの入口を越えられるからである。所有テナントの無い表の値（受注・発注・出荷依頼の一覧を取引先の名前で並べるときのテナントの名前）は、相手の公開 API が scope を掛けずに、返す列を ID と名前に絞った副問い合わせを同じ値で返す（`../adr/010-状況の導出をSQLの式1つにする.md` 決定 2）。
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
| `shared` | 視点を問わない葉の型。スカラーと enum と他の `shared` の型だけをフィールドに持つ | `Tenant`（ID と名前だけ）・`UserError`・`PageInfo`・`AuditLog` |
| `root` | ルートの型。視点の入口と `viewer`、または mutation を束ねる | `Query`・`Mutation` |

mutation の戻り値・コネクション・エッジの型は視点を宣言しない。mutation の戻り値の型は mutation の視点を、コネクションとエッジの型は中身の型の視点を、基底クラス（`Types::BasePayload`・`Types::BaseConnection`・`Types::BaseEdge`）が返す。

型の名前は、所有するコンテキストの言葉で付ける。同じ出荷実績でも、受注側の型は `Shipment`、発注側が経路 3 で見る型は `SupplierShipment`、購買が持つ写しの型は `InboundShipment` になる。

mutation は入れ子にせず、`Mutation` の直下に並べる。GraphQL は最上位の mutation だけを順に実行し、入れ子のフィールドは並行に解決するからである。視点は、mutation のクラスに宣言する。

### 相手側の型へたどれないことの保証

到達可能性のテスト（`spec/graphql/perspective_reachability_spec.rb`）が、CI で次の 5 つを確かめる。

1. `Query` のフィールドは `viewer`（`Viewer`）・`buyer`（`BuyerView`）・`supplier`（`SupplierView`）の 3 つだけである。`Mutation` のフィールドは、どれも `buyer` か `supplier` を宣言した mutation である。2 以降の検査は視点の入口と mutation から型をたどるので、ルートに直接置いた型は検査を素通りする。
2. `BuyerView` と、`buyer` を宣言した mutation の戻り値からたどれる型は、すべて `buyer` か `shared` である。`SupplierView` 側も同様に確かめる。
3. `shared` の型のフィールドは、スカラー・enum・`shared` の型だけを返す。
4. `buyer` の型のうち、相手テナントのデータを返す型は、`PublishedCatalogItem`・`SupplierPartnership`・`SupplierShipment` の 3 つに限られる。各型は、対応する読む経路を宣言する（`cross_tenant_read :catalog`・`:partnerships`・`:shipments`）。`SupplierShipment` の中にだけ現れる明細の型 `SupplierShipmentLine` は経路を宣言せず、`SupplierShipment` と同じ規則（`view_shipments` の付与）で認可する。
5. `Viewer` からたどれる型は、すべて `shared` である。`Viewer` は視点の入口の外にあるので、2 の検査が届かない。

`Query` に受注側の型を返すフィールドを足すと、1 が落ちる。発注の型に受注へのフィールドを 1 本足すと、2 が落ちる。相手側の型を 4 つ目として足すと、4 が落ちる。`Viewer` に受注側の型を返すフィールドを足すと、5 が落ちる。

## 発注側の視点

発注側の型が持つのは、購買が所有するデータと、相手テナントを読む 3 つの経路だけである（`context-map.md`「テナントと所有」）。

| 経路 | 型 | 開く条件 | 呼ぶ公開 API |
|---|---|---|---|
| 1. カタログ | `SupplierPartnership.catalog` → `PublishedCatalogItem` | 有効な取引関係と `view_catalog` の付与 | `Sales::PublishedCatalog` |
| 2. 取引関係 | `BuyerView.suppliers`・`BuyerView.supplier` → `SupplierPartnership` | 有効な取引関係 | `Partnerships::Directory` |
| 3. 自社の発注に連結した出荷 | `PurchaseOrder.supplierShipments` → `SupplierShipment` | 有効な取引関係と `view_shipments` の付与 | `Fulfillment::PartnerShipments` |

開く条件は、各公開 API が取引関係の公開 API（`Partnerships::Access`）に問い合わせて判定する。条件を満たさなければ、公開 API は空を返す。GraphQL 層では、経路ごとにエラーにも `null` にもしない。ただし取引先を 1 社選ぶ `buyer.supplier` は、1 件を引く入口なので、ほかの 1 件を引く入口と同じく `null` を返す（「ID と `node`」）。取引関係が失効した時点で、3 つの経路はどれも空になり、RLS も同じ行を閉じる（`data-model.md`「RLS」）。

経路 3 の出荷実績は、購買が持つ写しの入荷（`InboundShipment`）と同じ出荷を指す。業務の正本は写しの入荷で、検収はこれに対して行う。経路 3 は、受注側の出荷実績そのものを、権限付与がある間だけ見せる。

相手側の型は、相手テナントの内部の ID を、フィールドにもコネクションのカーソルにも持たない。`PublishedCatalogItem` は品目 ID を、`SupplierPartnership` は取引関係 ID を、`SupplierShipment` は出荷実績 ID を返さない。それぞれ品目コード、受注側テナント、連結先の発注で識別する。`SupplierShipment` の明細の型 `SupplierShipmentLine` も、出荷明細 ID を返さず、自社の発注明細で識別する。到達可能性のテストが、これら 4 つの型に ID のフィールドが無いことを確かめる。購買が持つ相手側の ID（`data-model.md`「購買（`purchasing`）」）も、GraphQL のフィールドには出さない。

```graphql
type BuyerView {
  suppliers: [SupplierPartnership!]!
  "経路 2 の取引先を 1 社選ぶ。取引関係の無い相手・失効した相手・存在しないテナントは区別せず null"
  supplier(supplierTenantId: ID!): SupplierPartnership
  purchaseOrders(first: Int, after: String, orderBy: PurchaseOrderOrder, filter: PurchaseOrderFilter): PurchaseOrderConnection!
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
  "税抜の合計金額。受注確定の前の明細を含むと空"
  totalAmount: BigInt
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

以下の SDL は抜粋である。省いた型（`ShipmentRequestLine`・`ShippingInstruction`・`BillingTerm`・`InvoiceTaxSummary` など）は、`data-model.md` の表の列のうち、相手側を指す ID 列を除いたものをフィールドにする。ただし `ShipmentRequest.instruction` は有効な出荷指示だけを返すので、`ShippingInstruction` は `status` をフィールドにしない。

同じテナントの中で複数のコンテキストを束ねるフィールド（受注 → 出荷依頼、出荷依頼明細 → 受注明細）は、ルートパッケージで両方の公開 API を呼んで解決する。コンテキスト同士は依存しない（`context-map.md`「疎結合を守る規則」5）。

```graphql
type SupplierView {
  partnerships: [Partnership!]!
  items(first: Int, after: String, orderBy: ItemOrder, filter: ItemFilter): ItemConnection!
  item(id: ID!): Item
  partMappings(customerTenantId: ID, first: Int, after: String): PartMappingConnection!
  salesOrders(first: Int, after: String, orderBy: SalesOrderOrder, filter: SalesOrderFilter): SalesOrderConnection!
  salesOrder(id: ID!): SalesOrder
  stocks(first: Int, after: String, orderBy: StockOrder, filter: StockFilter): StockConnection!
  stockMovements(itemId: ID, first: Int, after: String, filter: StockMovementFilter): StockMovementConnection!
  shipmentRequests(first: Int, after: String, orderBy: ShipmentRequestOrder, filter: ShipmentRequestFilter): ShipmentRequestConnection!
  billingTerms: [BillingTerm!]!
  "未請求の請求対象明細"
  billableItems(customerTenantId: ID, first: Int, after: String): BillableItemConnection!
  invoices(first: Int, after: String): InvoiceConnection!
  invoice(id: ID!): Invoice
  dashboard: SupplierDashboard!
  imports(first: Int, after: String): ImportConnection!
  import(id: ID!): Import
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
  "税抜の合計金額。品番照合待ちの明細を含むと空"
  totalAmount: BigInt
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
  "今日の販売単価"
  unitPrice: BigInt!
  "単価の履歴。asOf の時点で正しいと信じていた行を、有効期間の順に返す。省けばいま"
  prices(asOf: ISO8601DateTime): [ItemPrice!]!
  taxRatePercent: Int!
  published: Boolean!
  "入出庫も引当もしていない品目は空"
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

type StockMovement {
  id: ID!
  item: Item!
  type: StockMovementType!
  quantity: Int!
  reason: String
  createdAt: ISO8601DateTime!
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
  "確定で振る。下書きは空"
  invoiceNumber: String
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

"販売単価の 1 行（adr/006）。validFrom は含み validTo は含まない。validFrom・validTo・recordedTo の空は、上限なしを表す"
type ItemPrice {
  id: ID!
  unitPrice: BigInt!
  validFrom: ISO8601Date
  validTo: ISO8601Date
  recordedFrom: ISO8601DateTime!
  recordedTo: ISO8601DateTime
  reason: String
}

type BillableItem {
  id: ID!
  customer: Tenant!
  salesOrderLine: SalesOrderLine!
  itemName: String!
  unitPrice: BigInt!
  "検収数量"
  quantity: Int!
  taxRatePercent: Int!
  "単価 × 検収数量。税を含まない"
  amount: BigInt!
  inspectedOn: ISO8601Date!
  "請求書の単価の説明。下書きの請求書と未請求の明細では、発行時の単価は空"
  priceExplanation: PriceExplanation!
}

type PriceExplanation {
  "受注明細に写した単価"
  orderedUnitPrice: BigInt!
  "受注明細が単価を引いた有効日"
  pricedOn: ISO8601Date!
  "請求書の発行の時点で、pricedOn の単価として信じていた値"
  unitPriceAsOfIssue: BigInt
  "いま分かっている、pricedOn の単価"
  unitPriceNow: BigInt!
}

type Import {
  id: ID!
  kind: ImportKind!
  status: ImportStatus!
  totalRows: Int
  appliedRows: Int!
  failedRows: Int!
  startedAt: ISO8601DateTime
  finishedAt: ISO8601DateTime
  "失敗した行。行番号の順"
  rowErrors(first: Int, after: String): ImportRowErrorConnection!
}

type ImportRowError {
  rowNumber: Int!
  message: String!
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

ID でレコードを引く入口は、視点の下に型ごとに置く（`buyer.purchaseOrder(id:)`・`supplier.salesOrder(id:)`・`supplier.item(id:)` など）。mutation も ID を引数で受け取り、公開 API に操作者と一緒に渡す。どちらも公開 API の scope を通るので、見えない ID は存在しない ID と同じ扱いになる。クエリでは `null` を返し、mutation ではユーザーエラー `NOT_FOUND` を返す。存在するが見えない、という区別を返さない。

相手テナントを指す引数も、テナントが存在するかどうかを明かさない。

- **取引関係を前提にする引数**（`placePurchaseOrder` の `supplierTenantId` など）：公開 API はテナントを引かず、`Partnerships::Access` の判定だけで扱う。存在しないテナントも、取引関係の無いテナント・失効したテナント・権限付与の無いテナントと同じ `NOT_PERMITTED` になる。クエリの `buyer.supplier(supplierTenantId:)` は、存在しないテナントも、取引関係の無いテナント・失効したテナントと同じ `null` を返す。
- **取引関係を結ぶ相手**（`establishPartnership`）：受注側の `admin` は、相手を発注側テナントの取引用コード（`tenants.partner_code`）で指定する。取引用コードは推測できない無作為の値で、発注側の `admin` が `viewer.partnerCode` で読み、受注側へ業務の外で伝える。一致するテナントが無ければ `NOT_FOUND` を返す。相手の名前は、取引関係を結んだ後に `Partnership.buyer` で初めて見せる。テナントの `code` は推測できるので、指定に使わない。使うと、総当たりで他社の名前を集められる。

## 認可：宣言の無い型・リゾルバ・mutation は拒否する

テナントをまたぐ可視性と、操作の許否は、次の 3 段で分担する。上の段は下の段の代わりにならない。

| 段 | 置き場 | 決めること | 決めないこと |
|---|---|---|---|
| 1. RLS | DB の行ごとのポリシー（`data-model.md`「RLS」） | 自社の行だけを読み書きさせる。相手の行は、読む 3 経路（カタログ・取引関係・自社の発注に連結した出荷）の粗い条件でだけ読ませる | 一覧に相手の行を混ぜるか、どの役割が操作できるか |
| 2. 可視範囲（scope） | 各コンテキストの Action Policy の `relation_scope` | 公開 API が返す行を、自社の行か、経路ごとの条件（権限付与・自社の発注）を満たす相手の行に絞る | 操作してよいか |
| 3. 規則 | 同じ policy の操作ごとの規則（`show?`・`cancel?` など） | 型・入口・mutation ごとに、その操作者に許すか。役割による制限もここに置く（「役割による制限」） | どの行が見えるか |

Active Record の関連は、どの段にも当たらない。関連はコンテキストの中だけに張り、別のコンテキストの値は公開 API で引く（`context-map.md`「疎結合を守る規則」）ので、自社の行か相手の行かは関連では決まらない。

以下、2 段目と 3 段目を述べる。

- **可視範囲（scope）**：各コンテキストの policy の `relation_scope` に置く。コンテキストの公開 API は、操作者を必須の引数に取り、内部で scope を掛けてから値を返す。操作者を渡さずにレコードを返す公開 API は作らない。scope は所有の条件を明示し、RLS に任せない。自社のデータを返す scope は `owner_tenant_id` が操作者のテナントであることを、経路 3 の scope は `buyer_tenant_id` が操作者のテナントであることと権限付与を条件にする。RLS は経路 1〜3 の相手の行も返すので、RLS に任せると、受注側の一覧や ID 指定の入口に相手の公開品目・取引関係・出荷が自社の物として混ざる。型の `show?` も同じ条件で判定する。
- **操作者のいない入口の公開 API**：ジョブ・rake タスク・イベントの受け手・認証には、代わって操作する人がいない。この入口から呼ぶ公開 API は操作者を取らず、次の 3 つを守る。`Tenancy.require_tenant!` を通し、テナントの設定の外では例外にする。所有の条件を `Current.tenant_id` で明示し、RLS に任せない。レコードではなく、ID・件数・真偽値・値を返す。架空のシステムの操作者を作って渡さない。監査の行は、人の操作を `actor_type` の `user`、操作者のいない入口の書き込みを `system` と書き分けており（`data-model.md`「監査ログ（`platform`）」）、架空の操作者を渡すとこの区別が薄まるからである。テナントが決まる前の入口だけは、`Tenancy.require_tenant!` を通さない。ログインの `Partnerships::Authentication.authenticate` は RLS の外で動く認証専用の関数でメールアドレスから引き、シードと E2E の準備がテナントを作る `Partnerships::Onboarding.register` は、作ったテナントの中でだけユーザーを書く。同じ準備が、作った世界をもう一度作らないために引く `Partnerships::Onboarding.tenant_id(code:)` も、テナントが決まる前の入口で、テナントの ID だけを返す。どちらも、本番の環境では `DEMO_WORLD_ENABLED=1` を渡したプロセスでだけ呼べる（`Platform::DemoWorldGate`）。公開の配置は、この変数を毎日の作り直しにだけ渡し、Web とワーカーには渡さない（`../adr/009-デモを流用元と同じRaspberryPiのk3sに置き共有のデータを毎日作り直す.md` 決定 4）。在庫の品目の写しを書く `Inventory::ItemLabels.put` と、それを元から作り直す `Sales::Catalog.rebuild_item_labels`（rake タスク `read_models:rebuild` が呼ぶ）も、この入口の公開 API で、件数だけを返す。同じタスクが出荷依頼の受注番号の写しを作り直すために呼ぶ `Sales::SalesOrders.order_numbers`（受注の ID と受注番号の組を返す）と `Fulfillment::ShipmentRequests.put_order_numbers`（書き直した数を返す）も、この入口の公開 API である。`put` は品目の保存と取り込み（操作者のいる入口）の中からも呼ばれるが、写しは誰が保存しても同じ値になるので、操作者を取らない（`../adr/011-在庫の一覧のために品目のコードと名前を同期で写す.md`）
- **型・入口・操作ごとの規則**：GraphQL の基底クラスが、宣言された policy の規則を評価する。

policy は、コンテキストの公開 API として `packs/<パッケージ>/app/public/<名前空間>/` に置く。GraphQL 層は、公開 API が返す値に対して同じ policy の規則を評価する。scope と規則が同じ policy クラスにあるので、可視範囲の定義は 1 か所に保たれる（`decisions.md` 2 章「可視範囲」）。

業務の不変条件は、policy ではなく公開 API の中で確かめる。発注の登録時の `place_orders` の問い合わせ、出荷済みの受注の取消の拒否などがこれに当たり、違反はユーザーエラーとして返す（「エラー」）。

### 基底クラス

実装者は、型・リゾルバ・mutation を必ず次の基底クラスから作り、宣言を書く。宣言が無ければ、実行時に拒否する。

| 基底クラス | 必須の宣言 | 実行時の動き |
|---|---|---|
| `Types::BaseObject` | `perspective`（視点）と、`authorize_with <Policy>` か `authorization_exempt reason:` のどちらか | graphql-ruby の `authorized?` で、返すオブジェクトごとに policy の `show?` を評価する。同じ値を別の視点の型でも見せる型は、その視点の規則を `authorize_with <Policy>, :<規則>` で渡す（`SupplierPartnership` の `show_to_buyer?`）。宣言が無ければ拒否する |
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
| `Viewer` | ログイン中のユーザーと自社テナントを返す。`auditLogs` はリゾルバで、自ら宣言する |
| `BuyerView`・`SupplierView` | データを持たない入口。フィールドはすべてリゾルバで、各自が宣言する |
| `Tenant` | ID と名前だけの葉。認可済みの型のフィールドか、自社のテナントを返す `viewer.tenant` としてだけ現れる |
| `UserError`・`PageInfo` | データを持たない |
| `PriceExplanation`・`ImportRowError` | 認可済みの型（`BillableItem`・`Import`）のフィールドとしてだけ現れる |
| `SupplierDashboard`・`SalesOrderStatusCount` | 自社の集計の入れ物と、その中の件数。`supplier.dashboard` のリゾルバが規則を評価し、各フィールドは自社の scope を掛けた公開 API の値を返す。中の在庫と出荷依頼は、`Stock`・`ShipmentRequest` の型が規則を評価する |
| 各 mutation の戻り値の型 | 中身の型が、それぞれ宣言を持つ |
| 各コネクションとエッジの型 | 中身の型が、それぞれ宣言を持つ |

例外を足すときは、この表と列挙テストの期待値を同じ変更で足す。

列挙テストは、スキーマの型が object・スカラー・enum・input だけであることも確かめる。interface と union は、異なる視点の型を 1 つのフィールドにまとめられるので、到達可能性のテストと列挙テストに検査を足すまで使わない。

### 役割による制限

どの操作をどの役割に許すかは、`context-map.md`「自社の中の役割」で決まる。`admin` に限る操作は、次の policy の規則が `user.admin?` を条件に含めて判定し、拒否は `FORBIDDEN` で返す。対象の無い操作は、操作者に対して評価する。入力で許す役割が変わる操作は、対象を引く mutation にし、入力の値を含む対象の値を作って規則に見せる。対象の無い操作の規則は操作者しか見られないからである。表に無い mutation の規則は、自社のユーザーなら役割を問わない。

| 操作 | mutation・フィールド | policy の規則 |
|---|---|---|
| 取引関係と権限付与を変える | `establishPartnership`・`revokePartnership`・`grantPermission`・`withdrawPermission` | `Partnerships::PartnershipPolicy#establish?`（対象なし）・`#manage?` |
| 取消依頼 | `requestPurchaseOrderCancellation` | `Purchasing::PurchaseOrderPolicy#request_cancellation?` |
| 検収 | `inspectInboundShipment` | `Purchasing::PurchaseOrderPolicy#inspect_receipt?` |
| 取消の審査の承認・却下 | `approveCancellationReview`・`rejectCancellationReview` | `Sales::SalesOrderPolicy#review?` |
| 受注側の取消 | `cancelSalesOrder` | `Sales::SalesOrderPolicy#cancel?` |
| 請求条件の設定・締め・下書きの破棄・確定 | `setBillingTerm`・`closeBillingPeriod`・`discardDraftInvoice`・`issueInvoice` | `Billing::InvoicePolicy#set_term?`（対象なし）・`#close?`（対象なし）・`#discard?`・`#issue?` |
| 単価の改定の予約と訂正 | `scheduleItemPrice`・`correctItemPrice` | `Sales::ItemPolicy#change_price?` |
| 品目の CSV の取り込み | `startImport`（種類が `items` のとき） | `Imports::ImportPolicy#start?`（対象は取り込みの依頼の値で、置いたファイルと種類を持つ。種類が `items` なら `admin` に限り、`stocks` なら役割を問わない。取り込みのジョブも、チャンクごとに同じ規則を、取り込みを始めたユーザーのいまの役割で評価し直す） |
| 監査ログを読む | `viewer.auditLogs` | `Platform::AuditLogPolicy#index?` |

規則は、mutation の基底クラスが公開 API の操作を呼ぶ前に評価する。`member` が `admin` に限る mutation を呼ぶと、何も書かれずに `FORBIDDEN` になる（「1 回のリクエストがたどる道」1 のロールバック）。公開 API は役割を確かめないので、GraphQL を通らない入口（ジョブ・rake タスク・シード）から `admin` に限る操作の公開 API を呼ぶ人は、呼ぶ前に同じ規則を評価する。取り込みのジョブが、チャンクごとに `Imports::ImportPolicy#start?` を評価し直してから単価の改定の予約を呼ぶのがその形である。シードと E2E の世界を作る `DemoWorld` は、`admin` に限る操作を `DemoWorld::Operations`（`lib/demo_world/operations.rb`）からだけ呼ぶ。`Operations` は mutation の基底クラスと同じく、対象を公開 API で引いてから同じ規則を操作者で評価し、拒否なら公開 API を呼ばずに例外で止まる。`spec/scenarios/demo_world_spec.rb` が、`member` の操作者ではどの操作も止まることと、`DemoWorld` が `Operations` の外から `admin` に限る公開 API を呼ばないことを確かめる。入口の行列（`spec/matrix/graphql_matrix_spec.rb`）は、読み取りと mutation のすべての行に許す役割を持ち、全ペルソナの `member` でも呼ぶ。`admin` に限る mutation は、値を返すペルソナの `member` に `FORBIDDEN` になって何も書かないことを確かめる。`admin` に限る読み取りは、`member` に返す結果を行ごとに持ち（`viewer.auditLogs` は `FORBIDDEN`、`viewer.partnerCode` は `null`）、どのペルソナの `member` にもその結果になることを確かめる。`member` に許す行は、どのペルソナの `member` にも `admin` と同じ結果になり、mutation が値を返さないときは何も書かないことを確かめる。役割を問わない読み取りの規則に誤って `user.admin?` を足すと、`member` の結果が `FORBIDDEN` に変わって落ちる。入力で許す役割が変わる mutation は、行列に変種ごとの行（`Mutation.startImport` と `Mutation.startImport#stocks`）を持つ。

自社テナントの取引用コード（`viewer.partnerCode`）も、`admin` にだけ返し、`member` には空を返す。取引用コードを知った者は、受注側として取引関係を結べるからである。自社テナントの ID と名前は、`viewer.tenant`（`Tenant`）が役割を問わずに返す。`Tenant` は取引用コードを持たないので、`viewer.tenant` から取引用コードは届かない。

### 監査ログ

監査ログには、相手テナントに効果が及ぶ書き込みを記録する。何がそれに当たるかは `decisions.md` 2 章「監査」にある。本デモで書き込みが起きる入口は、mutation・イベントのジョブ・取り込みのジョブの 3 つである。記録は mutation とイベントのジョブの基底クラスが行い、個々の操作で手書きしない。取り込みのジョブは、相手に見えるカタログを書くが記録しない。取り込みを始めた `startImport` の監査の行が、誰がいつどのファイルを取り込んだかを残し、反映はその取り込みの結果として `supplier.import` で読めるからである。シードと E2E の世界を作る `DemoWorld` も、`admin` の操作者で相手に効果が及ぶ公開 API を呼ぶが、記録しない。人の操作ではなくデモの準備の書き込みで、本番の環境では `DEMO_WORLD_ENABLED=1` を渡した公開の配置の作り直しでだけ動くからである。そのため、シードの直後の監査ログには、イベントのジョブが書く受信の行（`event.received`）だけが並ぶ（OI-141）。

mutation の実装者は、認可の宣言と並べて、監査の宣言を必ず書く。宣言は次の 2 つのどちらかで、宣言が無ければ認可の宣言と同じく、開発とテストでは例外、本番では拒否する。

- `audit "<action>", target: ..., counterparty: ...`：相手テナントに効果が及ぶ mutation。`target:` と `counterparty:` はラムダで、`perform` が成功の値を返した後に、成功の値（`result:`）・`find_target` で引いた対象（`target:`）・入力（`input:`）を受け取って評価する。`target:` は公開 API の値を返し、行の対象の型の名前は値のクラス名（`PartnershipValue` なら `Partnership`）から取る。複数の相手に効果が及ぶ操作は、相手を列挙せず `counterparty: nil` にする。
- `audit_exempt reason:`：効果が自社の中で閉じる mutation。同じテナントの中で受け渡すイベント（`allocateSalesOrder` が出す「出荷可能」など）しか出さない操作も、相手テナントに効果が及ばないのでこちらにする。

基底 mutation は、`perform` が成功の値を返したときだけ、リクエストのトランザクションの中で 1 行を書く。1 回の操作で書く行は 1 行である。行とトランザクションの関係は、「1 回のリクエストがたどる道」の閉じ方のとおりになる。

- **ユーザーエラー**：失敗を返した公開 API は、自分のセーブポイントまで書き込みを戻している。基底 mutation は監査の行を書かない。リクエストはコミットされるので、同じリクエストで先に成功した mutation の業務の行と監査の行は残る。
- **トップレベルのエラーと例外**：`GraphqlController` がリクエスト全体を戻す。先に成功した mutation の業務の行・監査の行・イベントのジョブも一緒に戻る。監査の行の INSERT が失敗したときも、例外として全体が戻る。

イベントの受信は、`Contracts::EventJob` が、受け手の `handle` を終えた後、同じトランザクションで `event.received` として 1 行書く。書くのは、付帯情報の発行元のテナントと宛先テナントが違うときだけである。操作者は `system`、対象はイベントの名前と `event_id`、因果 ID は `event_id`、相手テナントは発行元のテナントになる。受信の行は、イベントと受け手のテナントごとに 1 行である。同じイベントの 2 回目の配送では書かず、同じテナントに受け手が 2 つあっても、先に終えた受け手の 1 行だけになる（`data-model.md`「監査ログ（`platform`）」の一意索引）。受け手が例外を投げれば、受け手の書き込みと一緒に戻る。

宣言の種類は次の表のとおりである。後のマイルストーンで作る mutation も載せている。

| 宣言 | mutation |
|---|---|
| `audit` | `establishPartnership`・`revokePartnership`・`grantPermission`・`withdrawPermission`・`saveItem`・`setItemPublished`・`scheduleItemPrice`・`correctItemPrice`・`startImport`・`registerPartMapping`・`placePurchaseOrder`・`requestPurchaseOrderCancellation`・`approveCancellationReview`・`rejectCancellationReview`・`cancelSalesOrder`・`postShipment`・`inspectInboundShipment`・`issueInvoice` |
| `audit_exempt` | `allocateSalesOrder`・`adjustStock`・`createShippingInstruction`・`cancelShippingInstruction`・`setBillingTerm`・`closeBillingPeriod`・`discardDraftInvoice` |

`audit_exempt` の理由は、どれも「効果が自社の中で閉じる」である。`registerPartMapping` は、照合待ちの受注を確定させて「受注確定」を出すので `audit` にする。

`audit` の mutation が書く行は、次の表のとおりである。mutation を作る人は、この表に行を足してから宣言を書く。

| mutation | action | 対象 | 相手 |
|---|---|---|---|
| `establishPartnership` | `partnership.establish` | 成功の値の取引関係 | その取引関係の発注側 |
| `revokePartnership` | `partnership.revoke` | 対象の取引関係 | その取引関係の発注側 |
| `grantPermission` | `partnership.grant_permission` | 対象の取引関係 | その取引関係の発注側 |
| `withdrawPermission` | `partnership.withdraw_permission` | 対象の取引関係 | その取引関係の発注側 |
| `saveItem` | `item.save` | 成功の値の品目 | 空（カタログを見る全相手に及ぶ） |
| `setItemPublished` | `item.set_published` | 対象の品目 | 空（カタログを見る全相手に及ぶ） |
| `scheduleItemPrice` | `item_price.schedule` | 対象の品目 | 空（カタログを見る全相手に及ぶ） |
| `correctItemPrice` | `item_price.correct` | 対象の単価の行 | 空（カタログを見る全相手に及ぶ） |
| `startImport` | `import.start` | 成功の値の取り込み | 空（品目の取り込みは、カタログを見る全相手に及ぶ） |
| `registerPartMapping` | `part_mapping.register` | 成功の値の対応表の行 | 入力の `customerTenantId`（確定させる受注は、すべてこの相手の受注である） |
| `placePurchaseOrder` | `purchase_order.place` | 成功の値の発注 | 入力の `supplierTenantId` |
| `requestPurchaseOrderCancellation` | `purchase_order.request_cancellation` | 対象の発注 | その発注の受注側 |
| `approveCancellationReview` | `cancellation_review.approve` | 対象の審査 | 成功の値の受注の発注側 |
| `rejectCancellationReview` | `cancellation_review.reject` | 対象の審査 | 成功の値の受注の発注側 |
| `cancelSalesOrder` | `sales_order.cancel` | 対象の受注 | その受注の発注側 |
| `postShipment` | `shipment.post` | 成功の値の出荷依頼から引いた出荷実績 | 出荷依頼の発注側 |
| `inspectInboundShipment` | `inbound_shipment.inspect` | 対象の入荷 | 成功の値の発注の受注側 |
| `issueInvoice` | `invoice.issue` | 対象の請求書 | その請求書の取引先 |

列挙テスト（`spec/graphql/authorization_declarations_spec.rb`）は、スキーマにある全 mutation が監査の宣言を持ち、宣言の種類と action が上の 2 つの表の行と一致することを確かめる。スキーマにある mutation が表に無ければ落ちる。表にあってスキーマにまだ無い mutation は比べない。監査の対象を変えたら、2 つの表を同じ変更で直す。

監査ログは、自社の `admin` が `viewer.auditLogs` で読む。`member` には `FORBIDDEN` を返す。リゾルバは `Viewer` の下にあるので、視点に `shared` を宣言する。型 `AuditLog` は `shared` で、伝票の型へのフィールドを持たず、対象を型の名前と ID の文字列で示す。相手テナントが書いた受信の行は相手のものなので、自社からは見えない。絞り込みの時刻は、`occurredFrom` 以上・`occurredTo` 未満である。

```graphql
type Viewer {
  # ユーザーのフィールドに加えて
  "自社テナント。取引用コードは含めない"
  tenant: Tenant!
  "admin だけ。新しいものから"
  auditLogs(first: Int, after: String, filter: AuditLogFilter): AuditLogConnection!
}

input AuditLogFilter {
  action: String
  correlationId: String
  occurredFrom: ISO8601DateTime
  occurredTo: ISO8601DateTime
}

type AuditLog {
  occurredAt: ISO8601DateTime!
  action: String!
  "ユーザーの名前。イベントの受信は空"
  actorName: String
  targetType: String!
  targetId: ID!
  counterparty: Tenant
  "運用者に問い合わせるときに伝える値"
  correlationId: String!
}
```

## 読み取りの一覧

各リゾルバが呼ぶ公開 API を示す。GraphQL 層が呼ぶ公開 API の名前は本書で決める。コンテキスト同士が呼ぶ公開 API（`Inventory::Allocation` など）は `context-map.md` が定める。

**発注側**

| フィールド | 呼ぶ公開 API |
|---|---|
| `buyer.suppliers`・`buyer.supplier` | `Partnerships::Directory.for_buyer`・`for_buyer_supplier` |
| `SupplierPartnership.catalog` | `Sales::PublishedCatalog.items` |
| `buyer.purchaseOrders`・`buyer.purchaseOrder` | `Purchasing::PurchaseOrders`（取引先の名前で並べるときは、取引関係の `Partnerships::Directory.tenant_names_sql` が返す副問い合わせを結ぶ） |
| `PurchaseOrder.lines`・`cancellationRequests`・`inboundShipments` | `Purchasing::PurchaseOrders`（発注 ID をまとめて渡す） |
| `InboundShipment.lines`・`inspection` | `Purchasing::PurchaseOrders.inbound_shipment_lines_for`・`inspections_for`（入荷 ID をまとめて渡す。検収数量は入荷の明細の値に含める） |
| `PurchaseOrder.supplierShipments` | `Fulfillment::PartnerShipments.for_purchase_orders` |
| `buyer.receivedInvoices`・`buyer.receivedInvoice` | `Purchasing::ReceivedInvoices` |
| `PurchaseOrder.supplier`・`ReceivedInvoice.supplier` | `Partnerships::Directory.tenants` |

**受注側**

| フィールド | 呼ぶ公開 API |
|---|---|
| `supplier.partnerships` | `Partnerships::Directory.for_supplier` |
| `supplier.items`・`supplier.item`・`Item` | `Sales::Catalog`。今日の単価で並べるときは `Sales::ItemPrices` の副問い合わせを、安全在庫で並べるときは在庫の公開 API `Inventory::Stocks` が返す副問い合わせを結ぶ |
| `supplier.partMappings` | `Sales::PartMappings` |
| `supplier.salesOrders`・`supplier.salesOrder`・`SalesOrder.lines` | `Sales::SalesOrders`（状況と引当数量は、受注の公開 API が在庫の `Inventory::Allocation` から得て返す。取引先の名前で並べるときは、取引関係の `Partnerships::Directory.tenant_names_sql` が返す副問い合わせを結ぶ） |
| `SalesOrder.cancellationReviews` | `Sales::CancellationReviews.for_sales_orders`（受注 ID をまとめて渡す） |
| `SalesOrder.customer` | `Partnerships::Directory.tenants` |
| `SalesOrder.shipmentRequest` | `Fulfillment::ShipmentRequests.for_sales_orders` |
| `supplier.stocks`・`Item.stock`・`supplier.stockMovements` | `Inventory::Stocks` |
| `supplier.shipmentRequests`・`ShipmentRequest.instruction`・`shipment` | `Fulfillment::ShipmentRequests`（取引先の名前で並べるときは、取引関係の `Partnerships::Directory.tenant_names_sql` が返す副問い合わせを結ぶ） |
| `ShipmentRequest.salesOrder`・`ShipmentRequestLine.salesOrderLine` | `Sales::SalesOrders` |
| `supplier.billingTerms` | `Billing::Terms` |
| `supplier.billableItems`・`Invoice.items` | `Billing::BillableItems`（`billableItems` は未請求の明細だけを返す。取引先でないテナントで絞ると空） |
| `supplier.invoices`・`supplier.invoice`・`Invoice.taxSummaries` | `Billing::Invoices`（集計は請求書 ID をまとめて渡す） |
| `BillingTerm.customer`・`BillableItem.customer`・`Invoice.customer` | `Partnerships::Directory.tenants` |
| `BillableItem.salesOrderLine` | `Sales::SalesOrders.lines_by_ids` |
| `supplier.dashboard` | `Sales::SalesOrders.count_by_status`・`Inventory::Stocks.below_safety_stock`・`Fulfillment::ShipmentRequests.due_within`・`Billing::BillableItems.unbilled_total` |
| `Item.unitPrice`・`Item.prices` | `Sales::Catalog`（今日の単価を `Sales::ItemPrices.price_at` で引いて品目の値に載せる）・`Sales::ItemPrices.history` |
| `BillableItem.priceExplanation` | `Sales::ItemPrices.explain`（ルートパッケージが、請求対象明細の受注明細 ID と請求書の発行時刻を渡す） |
| `supplier.imports`・`supplier.import`・`Import.rowErrors` | `Imports::Runs` |
| `viewer.tenant` | `Partnerships::Directory.tenants` |
| `viewer.auditLogs` | `Platform::AuditLogs`（「監査ログ」） |
| `AuditLog.actorName`・`AuditLog.counterparty` | `Partnerships::Directory.user_names`・`tenants` |

ダッシュボードは、factory-ops-demo の画面と同じく、複数のコンテキストの集計を 1 つの型に束ねる読み取り専用のクエリである。

```graphql
type SupplierDashboard {
  "集計の基準にした業務の今日（日本時間）"
  businessDate: ISO8601Date!
  "受注の 7 つの状況ごとの件数。0 件の状況も返す"
  salesOrderCounts: [SalesOrderStatusCount!]!
  "有効在庫が安全在庫より小さい在庫。品目コードの昇順で最大 100 件"
  stocksBelowSafetyStock: [Stock!]!
  "出荷期限が今日から 7 日以内の、出荷も取消もしていない出荷依頼。期限の昇順で最大 100 件"
  shipmentRequestsDueSoon: [ShipmentRequest!]!
  "未請求の請求対象明細の、単価 × 検収数量の合計（税抜き）"
  unbilledTotal: BigInt!
}

type SalesOrderStatusCount {
  status: SalesOrderStatus!
  count: Int!
}
```

集計の境界は次のとおりである。どれも自社のデータだけを数え、受注一覧と出荷依頼の一覧と同じ導出で状況を決める。今日は、ほかの業務の日付と同じく、アプリの時刻帯（`config.time_zone` の `Asia/Tokyo`）の `Date.current` で決める（`context-map.md`「検収と請求の流れ」）。リゾルバに時刻帯を直に書かない。

- **受注の件数**：受注一覧の状況（「状況の enum」の `SalesOrderStatus`）ごとに数える。取消済も 1 つの状況として数える。画面の受注一覧のタブの件数と一致させるためである。一覧の `statuses` と同じ状況の式で `GROUP BY` して数える。
- **安全在庫**：有効在庫（`on_hand - allocated`）が `safety_stock` より小さい在庫だけを返す。等しい在庫は返さない（`data-model.md`「在庫（`inventory`）」）。条件は在庫のモデルの scope（`Inventory::Stock.below_safety_stock`）の 1 つにあり、在庫の一覧の `filter: { belowSafetyStock: true }` も同じ scope で絞る。集計の数と、そこから飛ぶ一覧の件数を合わせるためである。在庫は品目コードを持たないので、品目コードでの並べ替えと 100 件の上限は、ルートパッケージが `Sales::Catalog.items_for` で引いたコードで行う。
- **出荷期限**：状況が出荷待ち・出荷指示済・出荷停止中の出荷依頼のうち、`due_date` が今日から 7 日後以下のものを返す。期限を過ぎたものも含める。状況は、出荷依頼の一覧の `statuses` と同じ式で絞る。
- **未請求の合計**：税は請求書・税率ごとに 1 回だけ丸めるので、締める前の明細には税額を出さず、税抜きの合計だけを返す。

`supplier.dashboard` のリゾルバは、規則に `Sales::SalesOrderPolicy#list?` を使う。ダッシュボードは受注の画面で、4 つの公開 API の一覧の規則はどれも、自社のユーザーなら役割を問わず許す。各フィールドは選ばれたときだけ公開 API を呼ぶ。

## mutation の一覧

各 mutation が呼ぶ公開 API と、その操作が同じトランザクションで出すイベントを示す。`admin` に限る mutation と、それを判定する規則は「役割による制限」の表にある。イベントを出すのは公開 API の中で、GraphQL 層はイベントを出さない。公開 API は、イベントのジョブをリクエストのトランザクションの中で登録する。ジョブはコミットまでワーカーから見えず、リクエストが戻ればジョブも消える（`../adr/005-イベントのジョブをトランザクション内で登録する.md`）。

**発注側**

| mutation | 呼ぶ公開 API | 出すイベント |
|---|---|---|
| `placePurchaseOrder` | `Purchasing::Ordering.place`（`Partnerships::Access` で `place_orders` を確かめる） | 発注登録 |
| `requestPurchaseOrderCancellation` | `Purchasing::Ordering.request_cancellation` | 取消依頼 |
| `inspectInboundShipment` | `Purchasing::ReceiptInspections.record`（入荷の全明細を 1 回で検収する。入力の規則は `context-map.md`「検収と請求の流れ」。同じ入荷への 2 回目は `CONFLICT`） | 検収完了 |

**受注側**

| mutation | 呼ぶ公開 API | 出すイベント |
|---|---|---|
| `saveItem`・`setItemPublished` | `Sales::Catalog`（`saveItem` は品目コードで自社の品目を引き、無ければ非公開で作り、あれば更新する。`saveItem` は公開の状態を変えない。公開の状態を変えるのは `setItemPublished` と、品目の CSV の取り込み（`published` の列）である。`unitPrice` は、作るときは有効期間 `(,)` の単価の行になる。既存の品目の単価は変えず、今日の単価と違う値は役割を問わず `INVALID_INPUT` にする。単価の改定は `scheduleItemPrice` を、入力の誤りは `correctItemPrice` を使う。今日の単価と同じ値は無視する） | なし |
| `scheduleItemPrice` | `Sales::ItemPrices.schedule`（品目 ID・単価・改定日で指定し、品目を返す。改定日は今日以降。改定日を含む行の単価と同じなら何も書かない。単価の行の無い品目は `CONFLICT`） | なし |
| `correctItemPrice` | `Sales::ItemPrices.correct`（単価の行 ID・正しい単価・理由で指定し、品目を返す。理由は必須。現在の行でなければ `CONFLICT`） | なし |
| `startImport` | `Imports::Runs.start`（`POST /imports/files` で置いたファイルの ID と種類で指定し、待機中の取り込みを返す。自社の置いたファイルでなければ `NOT_FOUND`、同じファイルの 2 回目と、置いてから 24 時間を過ぎて中身を消したファイルは `CONFLICT`（どちらも `path` は `["fileId"]`。中身を消したファイルは置き直しを促す文言。`data-model.md`「取り込み（`imports`）」）。ジョブはコミットの後に登録する） | なし |
| `registerPartMapping` | `Sales::PartMappings.register`（照合待ちの受注を照合し直す。取引先は自社が受注側の取引関係の相手に限り、それ以外と見えない品目は `NOT_FOUND`） | 全明細が照合できた受注ごとに受注確定 |
| `allocateSalesOrder` | `Sales::OrderAllocation.allocate`（`Inventory::Allocation` を同期で呼ぶ。品番照合待ち・取消済・出荷済の受注は `CONFLICT`） | 全量引当になったら出荷可能 |
| `cancelSalesOrder` | `Sales::OrderCancellation.cancel`（引当を解除する。出荷済・取消済の受注、未決の取消の審査がある受注、引当が消費済みの受注は `CONFLICT`） | 受注取消・出荷取消 |
| `approveCancellationReview` | `Sales::CancellationReviews.approve`（引当を解除する） | 取消承認・出荷取消 |
| `rejectCancellationReview` | `Sales::CancellationReviews.reject` | 取消却下・出荷停止解除 |
| `createShippingInstruction`・`cancelShippingInstruction` | `Fulfillment::Instructions`（どちらも出荷依頼 ID で指定する。取消は有効な指示を取り消す。取消済・出荷済の出荷依頼と、有効な指示の重複・不在は `CONFLICT`） | なし |
| `postShipment` | `Fulfillment::Shipping.post`（出荷依頼 ID と出荷日で指定し、有効な指示のある出荷依頼を全量で計上する。`Inventory::Allocation` で引当を消費し、`active` でない引当があれば `CONFLICT`） | 出荷計上 |
| `adjustStock` | `Inventory::Adjustment.adjust`（入庫・出庫。出庫は有効在庫までに限り、超えれば `INVALID_INPUT`。品目は在庫が受注に依存しないので、mutation が `Sales::Catalog` で自社の品目かを確かめ、見えなければ `NOT_FOUND`） | なし |
| `setBillingTerm` | `Billing::Terms.set`（取引先 ID と締め日。取引先は自社が受注側の取引関係の相手に限り、それ以外は `NOT_FOUND`） | なし |
| `closeBillingPeriod` | `Billing::Closing.close`（取引先 ID と締め日で、下書きの請求書を作る。入力と状態の結果は `data-model.md`「請求（`billing`）」） | なし |
| `discardDraftInvoice` | `Billing::Closing.discard`（請求書 ID で指定し、消した請求書の ID を返す。発行済みは `CONFLICT`） | なし |
| `issueInvoice` | `Billing::Closing.issue`（請求書 ID で指定し、確定した請求書を返す。入力と状態の結果は `data-model.md`「請求（`billing`）」） | 請求書発行 |
| `establishPartnership` | `Partnerships::Management.establish`（相手は発注側テナントの取引用コードで指定する。「ID と `node`」） | なし |
| `revokePartnership` | `Partnerships::Management.revoke` | なし |
| `grantPermission`・`withdrawPermission` | `Partnerships::Management` | なし |

受注側の ACL がイベントを受けて出すイベントは、上の表に載らない。ACL は、「発注登録」を受けて「受注確定」か「品番照合待ち」を、「取消依頼」を受けて「出荷停止」を（受注が出荷済みか取消済なら「取消却下」を）、「検収完了」を受けて「請求対象確定」を出す。取引関係の失効はイベントを出さない。失効の効果は、各公開 API が `Partnerships::Access` に問い合わせた時点で現れる（`context-map.md`「取引関係の失効」）。

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

mutation が受け取る入力の件数と長さには上限を置く。公開 API が上限を定数で持ち、超えた入力は何も書かずに `INVALID_INPUT` のユーザーエラーで返す。GraphQL の型では上限を表さない。

| 入力 | 上限 | 違反の `path` |
|---|---|---|
| `placePurchaseOrder` の `lines` の件数 | 100（1 ページの件数の上限と同じ） | `["lines"]` |
| `PurchaseOrderLineInput.partNumber` の長さ | 64 文字 | `["lines", 添字, "partNumber"]` |
| `adjustStock` の `reason` の長さ | 200 文字 | `["reason"]` |
| `requestPurchaseOrderCancellation` の `reason` の長さ | 200 文字。空白だけの理由も `INVALID_INPUT` | `["reason"]` |
| `correctItemPrice` の `reason` の長さ | 200 文字 | `["reason"]` |
| `saveItem`・`scheduleItemPrice`・`correctItemPrice` の `unitPrice` | 9,223,372,036,854,775,807（列の型 `bigint` の最大値。取り込みの CSV の `unit_price` も同じ上限で行の失敗にする） | `["unitPrice"]` |
| `inspectInboundShipment` の `lines` の件数 | 100（発注の明細の上限と同じなので、入荷の全明細は必ず収まる） | `["lines"]` |

## 状況の enum

発注・受注・出荷依頼の状況は、`data-model.md`「状態は保存せず、時刻列から導出する」の表と同じ優先順で、公開 API が SQL の式で導出して返す。GraphQL 層は導出しない。取消の依頼中・審査中は状況に重ねて示すので、enum の値にせず、別の真偽値のフィールドにする。

3 つの一覧は、状況で絞る `statuses`（`SalesOrderFilter`・`PurchaseOrderFilter`・`ShipmentRequestFilter`）を持つ。画面が状況のタブで一覧を分け、タブごとの件数を `totalCount` で読むためである。値は enum の状況で、重ねて示すフィールド（取消の依頼中・審査中）は状況ではないので絞り込みに入れない。表示・絞り込み・件数は同じ式を読むので、一覧の `status` と、その状況で絞った一覧と、ダッシュボードの状況ごとの件数が食い違わない。

3 つの一覧は、状況でも並べる（`orderBy` の `STATUS`、「ページングと N+1」）。並べる順は、下の表の導出の優先順ではなく、業務の進み順である。状況のモジュールが進み順の一覧（`SORT_ORDER`）を持ち、公開 API は状況の式の値の、その一覧での位置で並べる。状況のモジュールの単体が、`SORT_ORDER` と導出の優先順（`ALL`）が同じ状況の集まりであることを確かめる。片方にだけ状況を足すと、足した状況の位置が空になり、黙って最後に並ぶからである。

| 一覧 | 状況で並べる順（`ASC`） |
|---|---|
| 受注 | 品番照合待ち・受注済・一部引当・引当済・出荷済・検収済・取消済 |
| 発注 | 送信済み・受注側で確認中・受注済・入荷予定・検収済・取消済み・受注側により取消 |
| 出荷依頼 | 出荷待ち・出荷指示済・出荷停止中・出荷済・取消済 |

| enum | 値（導出表の状況） | 重ねて示すフィールド |
|---|---|---|
| `PurchaseOrderStatus` | `SUPPLIER_CANCELLED`（受注側により取消）・`CANCELLED`（取消済み）・`INSPECTED`（検収済）・`INBOUND`（入荷予定）・`ACCEPTED`（受注済）・`AWAITING_SUPPLIER_CONFIRMATION`（受注側で確認中）・`SENT`（送信済み） | `PurchaseOrder.cancellationPending`（取消依頼中） |
| `SalesOrderStatus` | `CANCELLED`（取消済）・`INSPECTED`（検収済）・`SHIPPED`（出荷済）・`AWAITING_PART_MATCH`（品番照合待ち）・`ALLOCATED`（引当済）・`PARTIALLY_ALLOCATED`（一部引当）・`RECEIVED`（受注済） | `SalesOrder.cancellationReviewPending`（取消審査中） |
| `ShipmentRequestStatus` | `CANCELLED`（取消済）・`SHIPPED`（出荷済）・`ON_HOLD`（出荷停止中）・`INSTRUCTED`（出荷指示済）・`READY`（出荷待ち） | — |
| `ImportStatus` | `FAILED`（失敗）・`PARTIALLY_FAILED`（一部失敗）・`SUCCEEDED`（完了）・`APPLYING`（反映中）・`STAGING`（置き場へ写し中）・`QUEUED`（待機中） | — |

その他の enum は、保存された列の値をそのまま写す。

| enum | 値 | 元の列 |
|---|---|---|
| `PartnershipStatus` | `ACTIVE`・`REVOKED` | `partnerships.status` |
| `PartnershipPermission` | `VIEW_CATALOG`・`PLACE_ORDERS`・`VIEW_SHIPMENTS` | `partnership_grants.permission` |
| `CancellationOutcome` | `APPROVED`・`REJECTED`（空は回答待ち・審査中） | `cancellation_requests.outcome`・`cancellation_reviews.decision` |
| `InvoiceState` | `DRAFT`・`ISSUED` | `invoices.issued_at` の有無 |
| `StockMovementType` | `INBOUND`・`OUTBOUND`・`ALLOCATE`・`DEALLOCATE`・`SHIP` | `stock_movements.type` |
| `StockAdjustmentType` | `INBOUND`・`OUTBOUND`（`adjustStock` の入力。引当と出荷による移動は、引当と出荷計上の操作だけが起こす） | `stock_movements.type` |
| `ImportKind` | `ITEMS`・`STOCKS` | `imports.kind` |

## エラー

エラーは、利用者が直せるかどうかで 2 つに分ける。

| 種類 | 返し方 | 例 |
|---|---|---|
| ユーザーエラー | mutation の戻り値の `errors`。HTTP は 200。リクエストのトランザクションはコミットする | 入力の誤り、業務の不変条件の違反、見えない ID、取引関係の無い相手 |
| トップレベルのエラー | GraphQL の `errors`。`extensions.code` に種別を入れる。リクエストの書き込みはすべて戻る | 認証切れ、規則による拒否・宣言漏れ・scope と規則の食い違い（`FORBIDDEN`）、クエリの上限超過、想定外の例外 |

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

`FORBIDDEN` は 1 つのコードで返し、応答からは出どころを区別させない。運用者は、メトリクス（`graphql_top_level_errors_total` の `reason`。[config.md「メトリクス」](../guides/config.md#メトリクス)）で出どころを分けて見る。出どころは次の 3 つで、拒否した箇所が `ForbiddenError` に持たせ、`GraphqlController` が応答に載ったエラー（`result.context.errors`）から集める。拒否した箇所で数えると、null が伝わって応答から消えた位置の拒否まで数え、応答の `FORBIDDEN` より多くなるからである（graphql 2.6.11 の `lib/graphql/execution/interpreter/runtime.rb`）。

| 出どころ | 拒否する箇所 | 起きる場面 |
|---|---|---|
| `rule` | リゾルバと mutation の規則（役割を含む。`AuthorizationDeclarations#enforce_rule!`） | `member` が `admin` に限る操作を呼んだ。画面がボタンを隠していても、利用者の操作で起こりうる |
| `object` | 返すオブジェクトとフィールドの規則（`FactoryOpsSchema.unauthorized_object`・`unauthorized_field`） | 公開 API の scope と型の規則が食い違った。テナントの境界の不具合の兆しである |
| `undeclared` | 宣言の無い型・リゾルバ・mutation（本番だけ。開発とテストは例外で落とす） | 宣言を忘れた入口が本番に出た |

mutation の戻り値（payload）は null を許さない（`Payload!`）。規則で拒否した mutation の null は `data` まで伝わり、同じ要求に並べた mutation のうち、先に成功したものの payload も返さない。トップレベルのエラーがある要求は書き込みをすべて戻すので、成功の payload を返すと、戻した書き込みを成功に見せるからである。ユーザーエラーは payload の `errors` で返るので、並べたほかの mutation の payload と書き込みは残る（`spec/requests/mutation_payload_spec.rb`）。

公開 API の操作は、成功なら値、失敗ならエラーコードと対象の入力項目を持つ結果の値（`OperationResult`、`packs/platform`）を返す。基底 mutation が、それを `UserError` に写す。入力項目は `[:lines, 0, :unit_price]` のように公開 API の名前で返し、基底 mutation が `path` の GraphQL の名前（`["lines", "0", "unitPrice"]`）に直す。公開 API の操作は、業務の不変条件の違反で例外を投げない。失敗を返す操作は、書き込みを `transaction(requires_new: true)` の中で行い、失敗を返す前にそのセーブポイントまで戻す。操作はリクエスト全体のトランザクションの中で動くので、入れ子の `transaction` で `ActiveRecord::Rollback` を投げても書き込みは戻らず、リクエストの終わりにコミットされる。セーブポイントまで戻すと、その中で登録したイベントのジョブも一緒に戻る。

## ページングと N+1

一覧は Relay のコネクションで返し、ページングの引数は `first`・`after` だけにする（前へは辿らない）。どのコネクションも件数 `totalCount` を持つ。件数は絞り込んだ一覧の行の数で、`first`・`after` に左右されない。ほかに一覧が持つ引数は、親を ID で選ぶもの（`partMappings(customerTenantId:)`・`stockMovements(itemId:)`・`billableItems(customerTenantId:)`）、監査ログの絞り込み（`AuditLogFilter`）、画面（`../implementation-plan.md` M33）が一覧を 1 ページずつ読むための並べ替え（`orderBy`・`thenBy`）と絞り込み（`filter`）である。並べ替えと絞り込みを持つ一覧は次の表のとおりで、ほかの一覧は件数だけを持つ。`orderBy` が 1 つ目の並べ替えの列、`thenBy` が 2 つ目からの列で、合わせて 3 つまで並べる。同じパッケージの値（一覧の表の列と、そこから計算する合計金額と状況）は SQL の式で並べる。別のコンテキストの値は、相手の表を直に結合せず、相手の公開 API が返す副問い合わせ（取引先の名前・品目の安全在庫）か、一覧のパッケージに写した値（在庫の品目のコードと名前・出荷依頼の受注番号。`../adr/011-在庫の一覧のために品目のコードと名前を同期で写す.md`）で並べる。相手の表を直に結合すると、相手の scope と列の名前が一覧のパッケージに出て、公開 API が値を返す境界（「1 回のリクエストがたどる道」3）を越えるからである。受注・発注・出荷依頼は、導出した状況でも絞る（`statuses`、「状況の enum」）。

| 一覧 | 並べ替えの列（`<型>OrderField`） | 絞り込み（`<型>Filter`） |
|---|---|---|
| `supplier.salesOrders` | `ORDER_NO`・`ORDER_DATE`・`DUE_DATE`・`CUSTOMER_NAME`・`TOTAL_AMOUNT`・`STATUS` | `customerTenantId`、`orderDateFrom`・`orderDateTo`、`statuses` |
| `buyer.purchaseOrders` | `ORDER_NO`・`ORDER_DATE`・`DESIRED_DELIVERY_ON`・`SUPPLIER_NAME`・`TOTAL_AMOUNT`・`STATUS` | `supplierTenantId`、`orderDateFrom`・`orderDateTo`、`statuses` |
| `supplier.shipmentRequests` | `ORDER_NO`・`DUE_DATE`・`PLANNED_DATE`・`CUSTOMER_NAME`・`STATUS` | `statuses` |
| `supplier.stocks` | `ITEM_CODE`・`ITEM_NAME`・`ON_HAND`・`ALLOCATED`・`AVAILABLE`（`on_hand - allocated`）・`SAFETY_STOCK` | `belowSafetyStock`、`keyword` |
| `supplier.stockMovements` | — | `types` |
| `supplier.items` | `CODE`・`NAME`・`UNIT`・`UNIT_PRICE`・`SAFETY_STOCK` | `keyword` |

- 伝票番号は `PO-000001` の形の、桁をそろえた文字列である（`DocumentNumber`）。文字列の順が番号の順になるので、`ORDER_NO` は列をそのまま並べる。出荷依頼の `ORDER_NO` は、出荷が受注に依存しないので、「出荷可能」のイベントで運んで出荷依頼に写した受注番号（`shipment_requests.sales_order_no`、`data-model.md`「出荷（`fulfillment`）」）で並べる。表示の受注番号は、いまと同じく `ShipmentRequest.salesOrder` から受注の値を出す。写しの空の出荷依頼（作り直しのタスクを流す前の既存の DB）は、値の無い行として最後に並ぶ。
- 取引先の名前（`CUSTOMER_NAME`・`SUPPLIER_NAME`）は、取引関係の公開 API `Partnerships::Directory.tenant_names_sql` が返すテナントの ID と名前の副問い合わせから、伝票の相手のテナント ID（受注の `customer_tenant_id`・発注の `supplier_tenant_id`・出荷依頼の `buyer_tenant_id`）の行の名前を、行ごとに 1 つ引くスカラーの副問い合わせ（`SqlSubquery#lookup`）で並べる。結合と違い、結ぶ条件を書き誤って 2 行以上が当たると、行を増やさずに SQL のエラーになる。名前は `tenants.name` の照合順序 `ja-x-icu` で並べ、流用元の画面の `Intl.Collator("ja")` と同じ規則の並びになる（同じと言える範囲は `data-model.md`「文字列の照合順序」）。名前全体の読みの順ではなく、よく使う漢字はその漢字の音読みの順に並ぶ。
- 合計金額（`TOTAL_AMOUNT`）は、明細の数量と単価の積の和を、受注は `Sales::SalesOrderAmount`、発注は `Purchasing::PurchaseOrderAmount` の SQL の式で計算して並べる。単価の無い明細（受注は品番照合待ち、発注は受注確定の前）が 1 つでもあれば、合計は空になり、値の無い行として最後に並ぶ。一覧の `totalAmount` も同じ式を読むので、空の合計は、どの画面でも金額の代わりに空の理由（「照合待ち」・「確定待ち」。取り消した伝票は「取消」）を出し、一部の合計を出さない（`frontend/lib/format.ts` の `totalAmountText`。伝票の状況を受け取る）。単価は `bigint` の上限まで入りうるので、積と和は `numeric` で計算する。和は、明細の件数の上限（100）・数量の上限（`integer`）・単価の上限（`bigint`）の積を超えないので 31 桁に収まる。
- 状況（`STATUS`）は、状況の式の値を業務の進み順の位置で並べる（「状況の enum」）。
- 品目の単価（`UNIT_PRICE`）は、受注の公開 API `Sales::ItemPrices.today_price` が返す、品目ごとに今日の単価の行を 1 つ引くスカラーの副問い合わせで並べる。条件は表示の `Item.unitPrice` が読む `price_at` と同じで、今日は Ruby の `Sales::ItemPrice.today` で渡す。単価は `bigint` まで入りうるので、カーソルには合計金額と同じく 10 進の文字列で書く。
- 品目の安全在庫（`SAFETY_STOCK`）は、在庫の公開 API `Inventory::Stocks.safety_stocks_sql` が操作者の scope を掛けて返す品目 ID と安全在庫の副問い合わせから、品目 ID の行を引くスカラーの副問い合わせで並べる。在庫の行の無い品目は、値の無い行として最後に並ぶ。
- 出荷依頼の出荷予定日（`PLANNED_DATE`）は、有効な出荷指示の出荷予定日を、状況の式が出荷指示を読むのと同じ条件で出荷依頼ごとに 1 行引くスカラーの副問い合わせで並べる。有効な出荷指示の無い出荷依頼は、値の無い行として最後に並ぶ。
- 在庫の品目コードと品目名（`ITEM_CODE`・`ITEM_NAME`）と在庫の `keyword` は、在庫のパッケージの品目の写し（`item_labels`、`data-model.md`「在庫（`inventory`）」）を、所有テナントと品目 ID の組で外部結合して読む。品目 ID だけで結ぶと、RLS が他社の写しを見せたときに、他社の名義で同じ品目 ID を指す写しを並びと検索に使う。写しの無い在庫は、値の無い行として最後に並び、`keyword` には当たらない。品目名（品目の一覧の `NAME` と在庫の `ITEM_NAME`）も、列の照合順序 `ja-x-icu` で取引先の名前と同じ規則の並びになる。
- 受注日と発注日の範囲は両端を含む。`orderDateFrom` が `orderDateTo` より後なら、空を返す。
- `belowSafetyStock` が真なら、ダッシュボードの `stocksBelowSafetyStock` と同じ scope で絞る（「読み取りの一覧」の安全在庫）。偽か省いたときは絞らない。
- `keyword` は、前後の空白（全角の空白を含む）を除いた文字列を、品目コードか品目名に含む品目（在庫の一覧は、その品目の在庫）に絞る。大文字と小文字を、ASCII の外の文字と全角の英字でも区別せず（列の照合順序による。`data-model.md`「文字列の照合順序」）、全角と半角は区別する。`%`・`_` は文字として扱う。空の文字列は絞らない。100 文字を超える `keyword` は、引数の検証でトップレベルのエラーにする。2 つの一覧の規則は `Keyword`（`packs/platform`）の 1 か所にあり、2 つの入力型は同じ上限（`Keyword::MAX_LENGTH`）を読む。
- `types` と `statuses` の空の配列は 0 件を返し、省くか `null` なら絞らない。
- 複数の絞り込みを同時に渡すと、すべてに当たる行に絞る。

```graphql
"どのコネクションも、nodes・edges・pageInfo と並べて持つ。nodes と edges は graphql-ruby の既定のまま null を許す"
type SalesOrderConnection {
  nodes: [SalesOrder]
  edges: [SalesOrderEdge]
  pageInfo: PageInfo!
  "絞り込んだ一覧の行の数。first と after によらない。選んだときだけ数える"
  totalCount: Int!
}

"どちらの向きでも、並べ替えの列の値の無い行を最後に置く"
enum OrderDirection { ASC DESC }

type SupplierView {
  "orderBy が 1 つ目の列、thenBy が 2 つ目からの列。thenBy の型は orderBy と同じ入力型のリストで、ほかの 4 つの一覧も同じ形で持つ"
  salesOrders(first: Int, after: String, orderBy: SalesOrderOrder, thenBy: [SalesOrderOrder!], filter: SalesOrderFilter): SalesOrderConnection!
}

input SalesOrderOrder { field: SalesOrderOrderField!, direction: OrderDirection! }
enum SalesOrderOrderField { ORDER_NO ORDER_DATE DUE_DATE CUSTOMER_NAME TOTAL_AMOUNT STATUS }
input SalesOrderFilter { customerTenantId: ID, orderDateFrom: ISO8601Date, orderDateTo: ISO8601Date, statuses: [SalesOrderStatus!] }

input PurchaseOrderOrder { field: PurchaseOrderOrderField!, direction: OrderDirection! }
enum PurchaseOrderOrderField { ORDER_NO ORDER_DATE DESIRED_DELIVERY_ON SUPPLIER_NAME TOTAL_AMOUNT STATUS }
input PurchaseOrderFilter { supplierTenantId: ID, orderDateFrom: ISO8601Date, orderDateTo: ISO8601Date, statuses: [PurchaseOrderStatus!] }

input ShipmentRequestOrder { field: ShipmentRequestOrderField!, direction: OrderDirection! }
enum ShipmentRequestOrderField { DUE_DATE CUSTOMER_NAME STATUS ORDER_NO PLANNED_DATE }
input ShipmentRequestFilter { statuses: [ShipmentRequestStatus!] }

input StockOrder { field: StockOrderField!, direction: OrderDirection! }
enum StockOrderField { ITEM_CODE ITEM_NAME ON_HAND ALLOCATED AVAILABLE SAFETY_STOCK }
input StockFilter { belowSafetyStock: Boolean, keyword: String }

input StockMovementFilter { types: [StockMovementType!] }

input ItemOrder { field: ItemOrderField!, direction: OrderDirection! }
enum ItemOrderField { CODE NAME UNIT UNIT_PRICE SAFETY_STOCK }
input ItemFilter { keyword: String }
```

`orderBy` を省いた一覧は、主キーの UUIDv7 で作成順の新しいものから並べ、主キーをカーソルにする。ただし相手側の型の一覧は、相手の内部の ID をカーソルに出さないため、型を識別する値で並べてカーソルにする（`SupplierPartnership.catalog` は品目コードの昇順）。取り込みの失敗した行（`Import.rowErrors`）は、行番号の昇順に並べ、行番号をカーソルにする。

`orderBy` を渡した一覧は「列 1、列 2、…、主キー」の組で並べ、列ごとに向きを持ち、主キーを最後の列と同じ向きに並べる。列の値が同じ行がページの境目をまたいでも、行は抜けも重なりもしない。値の無い行（希望納期の無い受注など）は、列ごとに向きによらず後ろに置く。カーソルの後ろの行は、「ある列より前の列がすべてカーソルと同じ値で、その列がカーソルより後」のどれかか、「すべての列が同じ値で、主キーが後」である。前の列が同じことは、空どうしも同じとみなす `IS NOT DISTINCT FROM` で比べる（`=` で比べると、前の列の値が空の行で、後ろの列がカーソルより後の行が抜ける）。列ごとの「後」は、カーソルの値が空なら無く、値があれば「値が後か、値が空」である。列が 1 つなら、後ろは、カーソルの値が空なら「値が空で主キーが後のもの」だけになり、値があれば「値が後のもの、値が同じで主キーが後のもの、値が空のもの」になる。カーソルは、列ごとの名前・向き・値を順に並べ、最後に主キーを置いた配列を JSON にして Base64 で包んだ不透明な文字列である。列が 1 つなら、名前・向き・値・主キーの 4 つになる。合計金額と品目の単価の値は、`bigint` を超えうるか `bigint` まで入るので JSON の数にせず整数の 10 進の文字列で書き、読むときは 31 桁までの数字だけを受け付ける。形の誤ったカーソルと、別の並べ替え（列の数・名前・向きのどれかの違うもの、`orderBy` の有無の違うもの）で作ったカーソルは、どれもトップレベルのエラー（`Invalid cursor`）にする。

`thenBy` は、`orderBy` を省いて渡すか、`orderBy` と合わせて 4 つ以上の列になるか、同じ `field` を 2 回書くと、引数の検証でトップレベルのエラーにする（`Resolvers::SortArguments`）。列を 3 つまでにするのは、カーソルの後ろの条件が列の数の 2 乗で長くなるからで、サーバーの上限は `Page::MAX_SORTS` に、画面の見出しで足せる列の数は `frontend/lib/list.ts` の `MAX_SORTS` にあり、`spec/graphql/sort_arguments_spec.rb` が 2 つを同じ値に保つ。2 つ目からの列を、`orderBy` をリストに変えずに別の引数で足したのは、`orderBy` の型を変えると比較器が破壊的な変更に分類するからである（`../implementation-plan.md` M47 の判断）。画面は、一覧の見出しを Shift を押して押すと 2 つ目からの列を足し、ダッシュボードのかんばんは、未完了の受注の列を希望納期と受注番号の順に読む。

公開 API は、操作者・件数・カーソル（並べ替えと絞り込みを持つ一覧は、それも）を受け取り、1 ページ分の値・値ごとのカーソル・次のページの有無・件数を `Page`（`packs/platform`）で返す。公開 API は scope と絞り込みを掛けた relation を `Page.of` に渡し、`Page` はページの行と件数を同じ relation から引く。ページと件数で scope と絞り込みを別々に書くと、片方だけ scope が抜けても単体の spec では気づきにくいからである。`Page` は、行と件数を初めて読まれたときに引く。`totalCount` だけを選ぶ問い合わせ（画面のタブの件数）は、件数の 1 つの SQL だけを流し、ページの行も値への写しも読まない。`Page` を作った `Tenancy.with_tenant` の外で行か件数を読むと、`Tenancy::MissingTenant` にする。テナントの設定の無い接続では、RLS が行を隠して空のページを黙って返すからである。リゾルバは公開 API を呼ぶブロックを `Connections::PagedQuery` に包んで返し、`Connections::PagedConnection` が、上限で丸めた件数とカーソルを渡してブロックを呼ぶ。形の誤ったカーソルは、トップレベルのエラーにする。

明細・権限付与・取引関係・請求条件のように、親ごとの件数が小さい集まりは、コネクションにせずリストで返す。

返すオブジェクトごとに評価する型の規則（「基底クラス」）も、オブジェクトの数だけクエリを出してはならない。規則がオブジェクトによらない問い合わせ（`Sales::ItemPolicy#show_to_buyer?` の、受注側ごとの `view_catalog` の問い合わせ）をするときは、`ApplicationPolicy#remember` に包む。一覧の要素ごとに相手が変わる規則は、相手ごとに覚えても相手の数だけ問い合わせが出るので、相手の集合を 1 回で引いて覚える（`Fulfillment::ShipmentRequestPolicy#show_to_buyer?` は、`view_shipments` を与えている受注側の集合を覚え、発注の一覧の出荷ごとにそこから引く）。`Types::BaseObject` は、1 回の実行の間だけ使うハッシュを `request_memo` として policy に渡し、`remember` はそこに答えを覚える。覚えた答えは同じ実行の中でしか使わないので、次のリクエストは失効や撤回を必ず見る。書き込みの前の判定（発注の登録の `place_orders`）は、覚えた答えを使わず、公開 API の中で毎回問い合わせる。

別のコンテキストの値や子の値を引くフィールドは、`GraphQL::Dataloader` のソースを通して公開 API を呼ぶ。公開 API は、そのために操作者と ID の配列を受け取り、ID ごとの値のハッシュを返す一括取得のメソッドを持つ（例：`Sales::SalesOrders.lines_for(actor, order_ids)`）。1 件ずつ引くメソッドを、入れ子のフィールドから呼ばない。ソースは `Sources::PublicApiSource` の 1 つで、公開 API のモジュール・メソッド名・操作者を引数に取り、操作者を公開 API にそのまま渡す。

N+1 は、2 つの検査で落とす（`../implementation-plan.md` M17）。

- **公開 API の中の N+1**：Bullet をテストで有効にし、関連を 1 件ずつ読むと例外にする。Bullet は検出の状態をスレッド変数に置くので、Dataloader のソースの Fiber の中の読み込みも見える。`spec/support/bullet.rb` が各 example を `Bullet.profile` で包む。HTTP の要求を流す example（`type: :request`）は、Bullet のミドルウェアが要求ごとに包むので外の包みから外し、要求の外でイベントを受け手まで流す補助が自分で検出を始める。競合テスト（`:concurrency`）は別のスレッドで操作し、Bullet に見えないので包まない。
- **フィールドの N+1**：GraphQL の型は AR のレコードではなく公開 API の値を受け取るので、親ごとに公開 API を呼ぶ N+1 は Bullet に見えない。画面の問い合わせごとに、親が 1 件と 20 件のときの SQL の件数が同じであることを、クエリ数の予算のテスト（`spec/graphql/query_budget_spec.rb`）で確かめる。

どちらの検査も、テストのデータが N+1 を出せなければ素通りする。テストを書く人は、次の 2 つを守る。

- **一覧のテストは、親を 2 件以上作る**：Bullet は、1 回の読み込みで 1 件しか返らなかったレコードを N+1 の候補にしない。一覧を返す公開 API のテストでは、親を 2 件以上作り、それぞれの関連を読む値を確かめる。準備のデータは factory で作り、確かめる公開 API は factory が終わった後に呼ぶ。Bullet は作ったレコードも候補から外すので、`spec/support/bullet.rb` は factory が動く間だけ検出を止めている。factory の属性やコールバックの中で公開 API を呼ぶと、その読み込みは検出されない。公開 API を呼んで準備したレコードは、候補にならない。
- **画面の問い合わせは、一覧の中にコネクションを入れ子にしない**：一覧の要素の下にコネクションを置くと、親ごとにページングの問い合わせが出る。コネクションは、親を 1 つに決めてから引く（カタログは `buyer.supplier(supplierTenantId:)` で取引先を 1 社選んでから引く）。画面の問い合わせは、操作名を付けて 1 ファイル 1 つで `frontend/graphql/<視点>/<操作名>.graphql` に置く。画面が実際に送る文書と、検査する文書を 1 つにするためである。query の文書は、クエリ数の予算のテストの表に、操作者・一覧の親・入れ子の件数を足す。表に無い query の文書と、リストの要素の下にコネクションを置いた文書があると、そのテストが落ちる。詳細の文書は詳細の下の配列（明細など）を一覧の親にし、一覧を持たない文書は、エラーなく実行できることだけを確かめる。1 ページの上限を文書に書いて読む一覧（ダッシュボードのかんばんの列の `first: 10`）は、表の一覧の行に上限を書き、返す件数を親の件数と上限の小さい方と比べる。画面の問い合わせは fragment を使わない。予算のテストが選択をたどるときに fragment を展開しないからである。

公開 API の中で親ごとに発行するクエリのうち、関連の読み込みでないもの（`where` で子を引き直す、など）は、Bullet にも、画面の問い合わせを通らない書き込みの経路ではクエリ数の予算にも見えない。一括で引くことを守りたい公開 API は、その spec で SQL の数を数える（`Sales::PartMappings.register` の spec）。

Dataloader のソースは、リクエストのトランザクションと同じ DB 接続で動かす。graphql-ruby の Dataloader はソースを別の Fiber で実行するので、`config.active_support.isolation_level` を既定の `:thread` のままにし、`GraphQL::Dataloader::AsyncDataloader` は使わない。`:fiber` にすると Fiber ごとに別の接続を取り、`SET LOCAL` の無い接続で引いたソースが例外ではなく 0 行を返す。

クエリには次の上限を設ける（`decisions.md` 6 章）。複雑度の上限は、1 ページの一覧を画面に必要なフィールドで取る問い合わせが通り、コネクションを入れ子にして件数が掛け算になる問い合わせが通らない値にする。graphql-ruby は、コネクションの要素（`nodes`・`edges` の下）の複雑度を `first` の値の倍で数え、`first` を省くと 1 ページの件数の既定（20）の倍で数える。`pageInfo`・`totalCount` のような要素でない選択は掛け算にしない（graphql 2.6.11 の [`GraphQL::Schema::Field#calculate_complexity`](https://github.com/rmosolgo/graphql-ruby/blob/v2.6.11/lib/graphql/schema/field.rb)。`first` が無いときの件数は `default_page_size || query.schema.default_page_size || max_page_size || query.schema.default_max_page_size`）。リストで返す明細と一覧は掛け算にならない。そのため、リストの要素の下のコネクション（`buyer.suppliers` の下の `catalog`）は複雑度では止まらず、画面の問い合わせの規則（一覧の中にコネクションを入れ子にしない）が止める。

| 上限 | 値 | 決め方 |
|---|---|---|
| 深さ（`max_depth`） | 10 | 視点の入口から明細の葉までが収まる |
| 1 ページの件数の既定（`default_page_size`） | 20 | `first` を省いた一覧が、上限まで膨らまない |
| 1 ページの件数の上限（`default_max_page_size`） | 100 | — |
| 複雑度（`max_complexity`） | 2,500 | 100 件の一覧で各行が 20 前後のフィールドを取ると 2,000 前後になり、通る。100 件の一覧の中に 100 件のコネクションを入れ子にすると 10,000 を超え、通らない |

画面の問い合わせの複雑度は、`spec/graphql/query_complexity_spec.rb` が、画面の問い合わせの一覧のファイルをすべて読み、`first` に 1 ページの件数の上限を渡して graphql-ruby の複雑度の解析で計り、上限に収まることを確かめる。一覧にファイルを足せば、表を書かなくても計る。

## スキーマの変更と非推奨

スキーマの形は、リポジトリの根の `schema.graphql` に書き出して commit する。型を変えた実装者は、`bin/rails graphql:schema:idl` で書き直し、同じ commit に入れる。書き直しを忘れると `spec/graphql/schema_dump_spec.rb` が落ちる。スキーマに `extra_types` で型を足さない。graphql-ruby 2.6 の書き出しは、`extra_types` の型を、フィールドから届く型とは別にもう一度書くので、`schema.graphql` に同じ型が 2 回並ぶ。共通の型（`Tenant`・`UserError`・`PageInfo` など）は、フィールドから届かせる（OI-47）。

クライアントを壊す変更（フィールド・引数・enum の値の削除、型の変更、必須の引数の追加）は、次の順で行う。

1. 消すものに `deprecation_reason:` を付け、代わりのフィールドを同じ変更で足す。この変更を main にマージする。
2. 消す変更は、別の PR で行う。フロントエンド（`../implementation-plan.md` M33）の公開の後は、非推奨を main に入れてから 30 日以上たってから消す。公開まではクライアントが無いので、日数の条件を置かない。

型の変更と必須の引数・入力項目の追加は、その場では行わない。新しい型か引数を持つフィールドを代わりに足し、古いフィールドを 1・2 の順で消す。非推奨のフィールドの型をその場で変えても、下の判定は通さない。

### 互換の判定

CI の lint のジョブは、PR と main への push のたびに `bin/check-schema-compat` を流す。スキーマを変えた実装者は、PR を出す前に手元でも流す。スクリプトは、基準の ref（環境変数 `BASE_REF`、既定は `origin/main`）と HEAD の分岐点（`git merge-base`）の `schema.graphql` と、作業中の `schema.graphql` を比べ、落とす変更が 1 つでもあれば失敗する。分岐点に `schema.graphql` が無いときも、比べられないので失敗する。結果の一覧は標準出力に書き、`$GITHUB_STEP_SUMMARY` があればそこにも書く。

基準の先端ではなく分岐点と比べるのは、ブランチを切った後に基準へ入ったフィールドや値が、それを知らない作業中のスキーマでは削除に見えるからである。

CI は、契機ごとに基準を選ぶ。`actions/checkout` は `fetch-depth: 0` で全ブランチを `origin/` の下に取り、PR では PR のマージ commit を checkout する（[actions/checkout](https://github.com/actions/checkout#usage)）。PR では、基準を PR の向き先（`origin/<base_ref>`）にする。分岐点は基準の先端になり、作業中のスキーマは基準の変更を含むので、手元と同じく PR の変更だけが比べられる。main への push では、基準を push の前の main の先端（`github.event.before`）にし、その push で main に入った変更を比べる。`origin/main` を基準にすると、分岐点が HEAD 自身になり、何も比べない。force push で push の前の先端がどの ref からも届かなくなると、分岐点が見つからずに失敗する。

判定は `lib/schema_compat.rb` が、graphql-schema_comparator が返す変更ごとに行う。変更は、比較器の変更のクラス名（`FieldRemoved` など）と座標（変更の `path`。`PurchaseOrder.lines`・`Query.order.id` の形）で識別する。規則は上から当て、先に当たった規則で決める。

| 順 | 変更 | 通すもの |
|---|---|---|
| 1 | 削除（`FieldRemoved`・`FieldArgumentRemoved`・`InputFieldRemoved`・`EnumValueRemoved`・`TypeRemoved`） | 消えた要素が、基準のスキーマで `@deprecated` だったもの。`TypeRemoved` は、基準のスキーマでその型を返すか受け取るフィールド・引数・入力項目がすべて非推奨だったもの。union とインターフェースを返すフィールドは、その型を返しうるので数える。非推奨のフィールドの引数は、フィールドと一緒に消せるので数えない |
| 2 | 型の変更（`FieldTypeChanged`・`FieldArgumentTypeChanged`・`InputFieldTypeChanged`） | 比較器が非破壊に分類するもの（出力の型を null 可から非 null にする、入力の型を非 null から null 可にする） |
| 3 | 必須の引数・入力項目の追加（`FieldArgumentAdded`・`InputFieldAdded` のうち比較器が破壊に分類するもの）と、非 null の引数・入力項目から既定値を外す変更（`FieldArgumentDefaultChanged`・`InputFieldDefaultChanged` のうち変更後に既定値が無いもの） | 無い。既定値を外す変更は、比較器が危険に分類するが、既存の問い合わせを必須の追加と同じく壊す |
| 4 | 上に当たらない変更 | 非破壊の変更と危険な変更（enum の値の追加など）。破壊的変更は落とす |

削除は、比較器の重大度（`breaking?`・`non_breaking?`）より先に見る。比較器は、出力にだけ使う enum の値の削除を非破壊に分類するので、重大度を先に見ると非推奨を経ない削除が通る。

比較器（graphql-schema_comparator 1.2.1）が変更として出さないものは、判定にかからない。入力型への `@oneOf` の追加と、ディレクティブの `repeatable` を外す変更がそれに当たり、どちらも既存の問い合わせを壊しうるので、レビューで止める。union のメンバーとインターフェースの実装は `@deprecated` を付けられないので、規則 4 で落ちた `UnionMemberRemoved`・`ObjectTypeInterfaceRemoved` を通すには、例外の一覧に行を書く。

### 例外の一覧

非推奨を経られない変更（秘密を漏らすフィールドを即座に消す、など）は、実装者が `docs/graphql/breaking-changes.yml` に行を足して通す。1〜4 で落とした変更は、同じクラス名と座標の行があるときだけ通る。

```yaml
- change: FieldRemoved          # 比較器の変更のクラス名
  path: PurchaseOrder.note      # 座標
  reason: 備考に相手テナントの担当者の連絡先を返していた
```

- `reason` が空の行があれば、一覧の読み込みで失敗する。
- クラス名か座標が違う行は、その変更を通さない。
- 比べた変更のどれにも当たらない行は、警告として一覧に出る。行の変更が main に入った後は、どの PR でも当たらなくなるので、実装者は気付いた PR で行を消す。
