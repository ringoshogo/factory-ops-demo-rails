# データモデル

`context-map.md` の 6 つのコンテキストを、PostgreSQL のテーブルに落とす。実装者がマイグレーションを書くときと、レビュー担当がテナント境界を確かめるときに読む。テナントの持ち方の一般原則は `decisions.md` 2 章に従い、本書はそれを本デモのテーブルに当てはめる。

## テナントの持ち方：全テーブルに共通の規則

実装者は、テーブルを足すたびに次の規則に従う。

- **所有テナント列**：テナントのデータを持つテーブルには、すべて `owner_tenant_id uuid not null` を持たせる。持たないのは `tenants` と Solid Queue の表（`solid_queue_*`）だけで、テナント列の列挙テスト（`decisions.md` 7 章）の除外宣言に理由を書く。
- **主キー**：`id uuid`。値は UUIDv7 で、DB の `DEFAULT uuidv7()` で作る（`../adr/003-主キーにUUIDv7を使う.md`）。Solid Queue の表は、Solid Queue のスキーマのまま `bigint` にする。
- **同じコンテキストの親子は複合外部キーでつなぐ**：親に `UNIQUE (owner_tenant_id, id)` を持たせ、子は `FOREIGN KEY (owner_tenant_id, 親_id) REFERENCES 親 (owner_tenant_id, id)` で参照する。親と子の所有テナントが食い違う行は、DB が拒否する。
- **コンテキストをまたぐ参照は ID 列だけにする**：外部キー制約を張らず、AR の関連も張らない（`context-map.md`「疎結合を守る規則」1）。相手テナントへの参照（`buyer_tenant_id`・`supplier_tenant_id`・`customer_tenant_id`）と、連結元の伝票への参照（`source_purchase_order_id` など）も同じ扱いにする。
- **金額と数量**：円の整数（`bigint`）と整数（`integer`）。単価・品目名・税率は、受け取った時点の値を写して持つ。マスタの後からの変更で、確定済みの伝票が変わらないようにするためである。
- **伝票番号**：所有テナントの中で一意（`UNIQUE (owner_tenant_id, order_no)`）。採番は、テナントごとの採番行を行ロックして行う。
- **時刻列**：全テーブルに `created_at`・`updated_at` を持たせる。追記だけの `stock_movements` は `updated_at` を持たない。以下の表では省略する。

## 状態は保存せず、時刻列から導出する

受注・発注・出荷依頼の状況は、状態の列に保存しない。業務上の出来事ごとに時刻列（`shipped_at` など）を持たせ、そこから優先順で導出する。姉妹プロジェクト `factory-ops-demo` と同じ方式である。

状態列を持つと、非同期のイベントが想定外の順で届いたときに遷移表から外れる。時刻列は、出来事が起きたかどうかだけを記録するので、届く順に左右されない。

**受注（受注側）の状況**は、受注の時刻列と明細、在庫の引当から導出する。

| 優先 | 状況 | 条件 |
|---|---|---|
| 1 | 取消済 | `cancelled_at` がある |
| 2 | 検収済 | `inspected_at` がある |
| 3 | 出荷済 | `shipped_at` がある |
| 4 | 品番照合待ち | `item_id` が空の明細がある |
| 5 | 引当済 | 全明細が全量引き当て済み |
| 6 | 一部引当 | 引当が 1 つ以上ある |
| 7 | 受注済 | それ以外 |

未決の取消の審査があれば、上の状況に「取消審査中」を重ねて示す。引当の量は在庫だけが持つので、受注は `Inventory::Allocation` の公開 API に受注明細 ID をまとめて渡して得る。受注は出荷に依存しないので、「出荷指示済」は受注の状況に含めない。画面で出荷指示の有無を示す場合は、ルートパッケージで出荷の公開 API と束ねる。

**発注（発注側）の状況**は、発注の時刻列と、購買の中にある取消依頼・入荷・検収から導出する。

| 優先 | 状況 | 条件 |
|---|---|---|
| 1 | 受注側により取消 | `supplier_cancelled_at` がある |
| 2 | 取消済み | `cancelled_at` がある |
| 3 | 検収済 | 入荷に検収がある |
| 4 | 入荷予定 | 入荷（出荷計上の写し）がある |
| 5 | 受注済 | `accepted_at` がある |
| 6 | 受注側で確認中 | `awaiting_match_at` がある |
| 7 | 送信済み | それ以外 |

回答待ちの取消依頼があれば、上の状況に「取消依頼中」を重ねて示す。取消依頼が却下されたら、取消依頼に回答を記録するだけで、発注は元の状況に戻る。却下の前の状況を覚えておく列は要らない。

**出荷依頼（受注側）の状況**は、出荷依頼の時刻列と、出荷のコンテキストの中にある出荷停止・出荷指示・出荷実績から導出する。

| 優先 | 状況 | 条件 |
|---|---|---|
| 1 | 取消済 | `cancelled_at` がある |
| 2 | 出荷済 | 出荷実績がある |
| 3 | 出荷停止中 | 同じ受注に、解除されていない出荷停止がある |
| 4 | 出荷指示済 | 有効な出荷指示がある |
| 5 | 出荷待ち | それ以外 |

## 取引関係と権限付与（`partnerships`）

相手テナントのデータを読めるかどうかは、すべてここで決まる。取引関係の公開 API は、「テナント X は Y に対して操作 Z をしてよいか」に対して、有効な取引関係と権限付与があるかどうかで答える。

| テーブル | 主な列 | 制約 |
|---|---|---|
| `tenants` | `code`・`name`・`partner_code`（取引用コード） | `code`・`partner_code` 一意。`partner_code` は推測できない無作為の値で、受注側が取引関係を結ぶ相手の指定に使う。テナント列を持たない（取引先の名前の表示に使う） |
| `users` | `owner_tenant_id`・`email`・`name`・`role`（`admin` / `member`） | `email` 一意 |
| `partnerships` | `owner_tenant_id`（受注側）・`buyer_tenant_id`（発注側）・`status`（`active` / `revoked`）・`revoked_at` | `(owner_tenant_id, buyer_tenant_id)` 一意。自分自身との関係は不可。`status` と `revoked_at` は一致する |
| `partnership_grants` | `partnership_id`・`permission`（`view_catalog` / `place_orders` / `view_shipments`） | `(partnership_id, permission)` 一意。取引関係と同じ所有テナント |

取引関係は受注側が結び、受注側が失効させる。失効させた取引関係は再び有効にしない。取引を再開するときは、受注側が新しい取引関係を結ぶ。

`place_orders` は相手のデータを読む権限ではない。購買が発注を登録するときに問い合わせる権限である。

## 各コンテキストのテーブル

以下の表は、`id`・`owner_tenant_id`・時刻列と、親子の複合外部キーを省略する。「→」は、外部キーを張らない ID 参照を表す。

### 受注（`sales`）

| テーブル | 主な列 | 制約・冪等キー |
|---|---|---|
| `items`（品目カタログ） | `code`・`name`・`unit`・`unit_price`・`tax_rate_percent`（8 / 10、既定 10）・`published` | `(owner, code)` 一意 |
| `customer_part_mappings`（得意先品番の対応表） | `customer_tenant_id`→・`customer_part_number`・`item_id` | `(owner, customer_tenant_id, customer_part_number)` 一意 |
| `sales_orders` | `order_no`・`customer_tenant_id`→・`source_purchase_order_id`→・`order_date`・`due_date`・`confirmed_at`・`shipped_at`・`inspected_at`・`cancelled_at` | `source_purchase_order_id` 一意（連結の冪等キー）。取消と出荷は両立しない。検収は出荷の後 |
| `sales_order_lines` | `source_purchase_order_line_id`→・`customer_part_number`・`item_id`・`item_name`・`unit_price`・`tax_rate_percent`・`quantity` | `source_purchase_order_line_id` 一意。照合前は `item_id` と写しの 3 列がすべて空、照合後はすべて埋まる |
| `cancellation_reviews`（取消の審査） | `sales_order_id`・`source_cancellation_request_id`→・`requested_at`（取消依頼の登録時刻の写し）・`decision`（`approved` / `rejected`、空は審査中）・`decided_at`・`decided_by_user_id` | `source_cancellation_request_id` 一意。審査中は受注ごとに 1 件（部分一意索引） |
| `inspection_records`（検収の記録） | `sales_order_line_id`・`shipment_id`→・`quantity`・`inspected_on` | `(shipment_id, sales_order_line_id)` 一意 |

### 在庫（`inventory`）

| テーブル | 主な列 | 制約・冪等キー |
|---|---|---|
| `stocks` | `item_id`→・`on_hand`・`allocated`・`safety_stock` | `(owner, item_id)` 一意。`on_hand >= allocated >= 0`（有効在庫が負にならない） |
| `allocations`（引当） | `sales_order_line_id`→・`item_id`・`quantity`・`status`（`active` / `released` / `consumed`） | `sales_order_line_id` 一意 |
| `stock_movements`（在庫移動履歴） | `item_id`・`type`（`inbound` / `outbound` / `allocate` / `deallocate` / `ship`）・`quantity`（正の数）・`reason`・`allocation_id` | 追記だけ。増減の向きは `type` が決める |

在庫を変える処理は、すべて 1 つの内部メソッドを通す。このメソッドは、`stocks` の更新と `stock_movements` の追記を同じトランザクションで行う。

### 出荷（`fulfillment`）

| テーブル | 主な列 | 制約・冪等キー |
|---|---|---|
| `shipment_requests`（「出荷可能」の写し） | `sales_order_id`→・`buyer_tenant_id`→・`source_purchase_order_id`→・`due_date`・`cancelled_at` | `sales_order_id` 一意 |
| `shipment_request_lines` | `sales_order_line_id`→・`source_purchase_order_line_id`→・`item_id`→・`quantity` | `sales_order_line_id` 一意 |
| `shipping_holds`（出荷停止） | `sales_order_id`→・`source_cancellation_review_id`→・`released_at` | `source_cancellation_review_id` 一意。解除前の停止は受注ごとに 1 件 |
| `shipping_instructions`（出荷指示） | `shipment_request_id`・`planned_date`・`status`（`active` / `cancelled`） | 有効な指示は出荷依頼ごとに 1 件（部分一意索引） |
| `shipments`（出荷実績） | `shipping_instruction_id`・`shipment_request_id`・`buyer_tenant_id`→・`source_purchase_order_id`→・`shipped_on` | `shipment_request_id` 一意（分納しない） |
| `shipment_lines` | `shipment_id`・`shipment_request_line_id`・`source_purchase_order_line_id`→・`quantity` | `shipment_request_line_id` 一意 |

出荷停止は、出荷依頼とは別のテーブルに置く。取消の審査は全量の引当より前にも始まるので、出荷依頼がまだ無い受注も止められる必要がある。

`shipments` は `buyer_tenant_id` と `source_purchase_order_id` の写しを、`shipment_lines` は `source_purchase_order_line_id` の写しを持つ。発注側が自社の発注に連結した出荷を読む経路（「RLS」）で、判定と、出荷明細を自社の発注明細に結び付けることに使う。発注側は `shipment_request_lines` を読めないので、出荷明細の側に写しが要る。

### 購買（`purchasing`）

| テーブル | 主な列 | 制約・冪等キー |
|---|---|---|
| `purchase_orders` | `order_no`・`supplier_tenant_id`→・`order_date`・`desired_delivery_on`・`awaiting_match_at`・`accepted_at`・`cancelled_at`・`supplier_cancelled_at` | 発注側の取消と受注側の取消は両立しない |
| `purchase_order_lines` | `part_number`（自社品番）・`quantity`・`confirmed_item_name`・`confirmed_unit_price` | `(purchase_order_id, part_number)` 一意 |
| `cancellation_requests`（取消依頼） | `purchase_order_id`・`reason`・`outcome`（`approved` / `rejected`、空は回答待ち）・`decided_at` | 回答待ちは発注ごとに 1 件（部分一意索引） |
| `inbound_shipments`（「出荷計上」の写し） | `purchase_order_id`・`shipment_id`→・`shipped_on` | `shipment_id` 一意 |
| `inbound_shipment_lines` | `purchase_order_line_id`・`shipped_quantity` | `(inbound_shipment_id, purchase_order_line_id)` 一意 |
| `receipt_inspections`（入荷検収） | `inbound_shipment_id`・`inspected_on` | `inbound_shipment_id` 一意（入荷 1 件に 1 回） |
| `receipt_inspection_lines` | `inbound_shipment_line_id`・`accepted_quantity` | `inbound_shipment_line_id` 一意。検収数量は出荷数量以下（登録時にアプリで確かめる） |
| `received_invoices`（「請求書発行」の写し） | `invoice_id`→・`supplier_tenant_id`→・`invoice_number`・`period_start`・`period_end`・`issued_on`・`subtotal`・`tax_total`・`total` | `invoice_id` 一意。`total = subtotal + tax_total` |
| `received_invoice_lines` | `purchase_order_line_id`・`item_name`・`unit_price`・`quantity`・`tax_rate_percent`・`amount` | — |

購買が持つ相手側の ID は、`supplier_tenant_id`・`shipment_id`・`invoice_id` の 3 つだけである。受注・受注明細・品目の ID は、イベントが運ばないので購買には入らない（「イベントの受け口と冪等キー」）。

### 請求（`billing`）

| テーブル | 主な列 | 制約・冪等キー |
|---|---|---|
| `billing_terms`（請求条件） | `customer_tenant_id`→・`closing_day`（1〜28、31 は末日） | `(owner, customer_tenant_id)` 一意 |
| `billable_items`（請求対象明細） | `customer_tenant_id`→・`shipment_id`→・`sales_order_line_id`→・`source_purchase_order_line_id`→・`item_name`・`unit_price`・`quantity`・`tax_rate_percent`・`inspected_on`・`invoice_id`（空は未請求） | `(shipment_id, sales_order_line_id)` 一意 |
| `invoices` | `customer_tenant_id`→・`invoice_number`・`period_start`・`period_end`・`issued_at`（空は下書き）・`subtotal`・`tax_total`・`total` | `(owner, invoice_number)` 一意。下書きは取引先ごとに 1 件（部分一意索引）。`total = subtotal + tax_total` |
| `invoice_tax_summaries` | `invoice_id`・`tax_rate_percent`・`taxable_amount`・`tax_amount` | `(invoice_id, tax_rate_percent)` 一意 |

受注側の担当者が締めを実行すると、請求は次の順に処理する。

1. 請求条件の行をロックして、同じ取引先の締めを直列にする。
2. 締め日以前に検収された未請求明細を、すべて集める。前回の締めの後に届いた、前の期間の検収も含める。
3. 下書きの請求書を作り、集めた明細の `invoice_id` を埋める。
4. 税率ごとに課税対象額を足し上げ、税額を 1 回だけ切り捨てて `invoice_tax_summaries` に書く。

担当者が下書きを破棄すると、明細の `invoice_id` は空に戻る。担当者が確定すると `issued_at` が入り、その後は請求書も明細も変更しない。

## 取消と出荷の競合を止める場所

受注の取消と出荷の計上は、別々のコンテキストで、別々の担当者が行う。両方が同時に進んでも、どちらか一方だけが成立するようにする。止める場所は、在庫の引当の行である。

- **出荷の計上**：出荷が在庫の公開 API で引当を消費する。引当の行をロックし、`active` でなければ計上を中止する。
- **受注の取消**：受注が在庫の公開 API で引当を解除する。引当の行をロックし、`consumed`（出荷済み）なら取消を中止する。

どちらも同期・同一トランザクションで在庫を呼ぶので、引当の行ロックが両者を直列にする。受注は、取消を確定した後に「出荷取消」を出し、出荷はそれを受けて出荷依頼と出荷指示を閉じる。出荷指示が閉じるまでの間に計上を試みても、引当がすでに解除されているので計上は中止される。出荷停止（`shipping_holds`）は、発注側からの取消依頼の審査中に計上を止めておくための業務上の手順である。競合の最後の防壁は、引当の行ロックが受け持つ。

ロックは、受注 → 受注明細（`id` 順）→ 在庫（`item_id` 昇順）→ 引当の順に取る。順序を揃えて、デッドロックを避ける。

## イベントの受け口と冪等キー

発行元は、業務データを書くのと同じトランザクションの中で、イベントをジョブとして登録する。キューの表（`solid_queue_*`）は業務データと同じ DB にあり、テナントの表ではない（`../adr/005-イベントのジョブをトランザクション内で登録する.md`）。

イベントの受け手は、ペイロードが示す宛先テナントを `Current` に設定して処理する。受け手が書くのは自社のテーブルだけである。重複して届いても結果が変わらないように、受け手ごとに冪等キーを決める。

| イベント | 発行元 → 受け手 | 運ぶ値 | 受け手が書く表 | 冪等キー |
|---|---|---|---|---|
| 発注登録 | 購買 → 受注 | 発注 ID、発注側・受注側テナント、明細（発注明細 ID・自社品番・数量）、希望納期 | `sales_orders`・`sales_order_lines` | `source_purchase_order_id` 一意 |
| 品番照合待ち | 受注 → 購買 | 発注 ID | `purchase_orders.awaiting_match_at` | 空のときだけ書く |
| 受注確定 | 受注 → 購買 | 発注 ID、明細（発注明細 ID・品目名・単価） | `purchase_orders.accepted_at`・明細の写し | 空のときだけ書く |
| 取消依頼 | 購買 → 受注 | 取消依頼 ID、発注 ID、依頼の登録時刻 | `cancellation_reviews` | `source_cancellation_request_id` 一意 |
| 取消承認・取消却下 | 受注 → 購買 | 取消依頼 ID | `cancellation_requests.outcome`・`purchase_orders.cancelled_at` | 回答が空のときだけ書く |
| 受注取消 | 受注 → 購買 | 発注 ID | `purchase_orders.supplier_cancelled_at` | 空のときだけ書く |
| 出荷取消 | 受注 → 出荷 | 受注 ID | `shipment_requests.cancelled_at`・有効な出荷指示の取消・出荷停止の解除 | 空のときだけ書く |
| 出荷可能 | 受注 → 出荷 | 受注 ID、発注側テナント、発注 ID、納期、明細（受注明細 ID・発注明細 ID・品目 ID・数量） | `shipment_requests`・`shipment_request_lines` | `sales_order_id` 一意 |
| 出荷停止 | 受注 → 出荷 | 審査 ID、受注 ID | `shipping_holds` | `source_cancellation_review_id` 一意 |
| 出荷停止解除 | 受注 → 出荷 | 審査 ID | `shipping_holds.released_at` | 空のときだけ書く |
| 出荷計上 | 出荷 → 受注・購買 | 出荷実績 ID、受注 ID、発注 ID、出荷日、明細（受注明細 ID・発注明細 ID・数量） | 受注：`shipped_at`／購買：`inbound_shipments`・明細 | 受注：空のときだけ書く／購買：`shipment_id` 一意 |
| 検収完了 | 購買 → 受注 | 出荷実績 ID、発注 ID、明細（発注明細 ID・検収数量）、検収日 | `inspection_records`・`sales_orders.inspected_at` | `(shipment_id, sales_order_line_id)` 一意 |
| 請求対象確定 | 受注 → 請求 | 発注側テナント、出荷実績 ID、受注明細 ID・発注明細 ID、品目名・単価・税率、検収数量、検収日 | `billable_items` | `(shipment_id, sales_order_line_id)` 一意 |
| 請求書発行 | 請求 → 購買 | 請求書 ID、受注側・発注側テナント、請求番号、締め期間、発行日、金額、明細（発注明細 ID・品目名・単価・数量・税率・金額） | `received_invoices`・明細 | `invoice_id` 一意 |

「出荷計上」は受注と購買の両方へ同じ値を運ぶ。購買は、受注 ID と受注明細 ID を保存しない。

## RLS

アプリの DB ロールは、テーブルの所有者でも、RLS を迂回できるロール（`BYPASSRLS`）でもない一般ロールにする。テナントは、トランザクションの中で `SET LOCAL app.tenant_id` で渡す。

```sql
CREATE FUNCTION current_tenant_id() RETURNS uuid LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('app.tenant_id', true), '')::uuid $$;
```

`app.tenant_id` が未設定なら、この関数は空を返し、どの行にも一致しない。テナントの設定を忘れたクエリは、例外ではなく 0 行になる。例外にする役目はアプリ側の基底クラスが受け持つ（`decisions.md` 2 章）。

`tenants` と Solid Queue の表を除く全テーブルに、同じポリシーを 1 つ付ける。Solid Queue の表には RLS を付けず、アプリの DB ロールに参照・書き込みの権限を与える。ワーカーはテナントを設定せずにキューを読むからである。

```sql
ALTER TABLE items ENABLE ROW LEVEL SECURITY;
ALTER TABLE items FORCE ROW LEVEL SECURITY;
CREATE POLICY owner_write ON items FOR ALL
  USING (owner_tenant_id = current_tenant_id())
  WITH CHECK (owner_tenant_id = current_tenant_id());
```

`WITH CHECK` が全テーブルで同じなので、どのテーブルにも相手テナントの名義では書けない。イベントの受け手も自社の名義で書くだけなので、この規則に例外は無い。

相手テナントのデータを読む 3 つの経路にだけ、読み取り専用のポリシーを足す。PostgreSQL は、同じ操作に対する複数の許可ポリシーを OR で結ぶ。そのため、足したポリシーは `SELECT` だけを広げ、書き込みは `owner_write` のまま変わらない。

```sql
CREATE FUNCTION partnership_active(supplier uuid, buyer uuid) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT EXISTS (SELECT 1 FROM partnerships p
                  WHERE p.owner_tenant_id = supplier AND p.buyer_tenant_id = buyer AND p.status = 'active') $$;

-- 経路 1：カタログ
CREATE POLICY partner_read ON items FOR SELECT
  USING (published AND partnership_active(owner_tenant_id, current_tenant_id()));
-- 経路 2：取引関係
CREATE POLICY partner_read ON partnerships FOR SELECT
  USING (buyer_tenant_id = current_tenant_id() AND status = 'active');
CREATE POLICY partner_read ON partnership_grants FOR SELECT
  USING (EXISTS (SELECT 1 FROM partnerships p WHERE p.id = partnership_id));
-- 経路 3：自社の発注に連結した出荷
CREATE POLICY partner_read ON shipments FOR SELECT
  USING (buyer_tenant_id = current_tenant_id() AND partnership_active(owner_tenant_id, buyer_tenant_id));
CREATE POLICY partner_read ON shipment_lines FOR SELECT
  USING (EXISTS (SELECT 1 FROM shipments s WHERE s.id = shipment_id));
```

- **関数と子テーブルは、RLS を通して読む**：`partnership_active` と子テーブルのポリシーは、呼び出し元の権限で `partnerships`・`shipments` を読む。そのため、親が見えるときだけ子が見え、失効した関係は判定でも見えない。関数を `SECURITY DEFINER` にしない。
- **RLS は粗い判定にとどめる**：RLS が判定するのは「所有テナントか、有効な関係があるか」までである。どの権限付与（`view_catalog`・`view_shipments`）があるかは、アプリの policy scope が判定する（`decisions.md` 2 章「RLS の役割」）。
- **ログインの前のユーザー検索**：ログインの時点ではテナントが決まっていないので、`users` を RLS の下では引けない。メールアドレスからユーザー ID と所有テナントだけを返す認証専用の関数を 1 つ置く。この関数だけを RLS の外で動かす。

> 上の DDL とポリシーは、PostgreSQL 16 で試作して確かめた（UUIDv7 の代わりに `gen_random_uuid()`）。受注側・発注側・無関係の 3 テナントで次を確認した。未設定では 0 行になる。発注側に見えるのは、公開品目 1 件・取引関係・出荷の 3 経路だけである。相手名義の INSERT は RLS が拒否し、相手の行への UPDATE は 0 行になる。他テナントの親を指す子は、複合外部キーが拒否する。失効すると 3 経路がすべて閉じる。
