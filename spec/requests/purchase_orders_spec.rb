require "rails_helper"
require_relative "../support/events"
require_relative "../support/shared_examples/idempotent_receiver"

# 発注登録と受注の連結。1 つの発注から受注が 1 件だけでき、照合の結果が発注の状況に写る。
# 発注できない相手は、理由を区別せず同じ NOT_PERMITTED にする（docs/architecture/context-map.md「発注の連結と品番の照合」）
RSpec.describe "発注登録と受注の連結", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant, name: "青嵐精機工業") }
  let!(:buyer) { FactoryBot.create(:tenant, name: "組立メーカー") }
  let(:supplier_member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }
  let(:buyer_actor) { actor_of(buyer) }
  let!(:partnership) do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders]) }
  end
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code: "BOLT-8", name: "六角ボルト M8", unit_price: 120) } }
  let!(:mapping) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:customer_part_mapping, customer_tenant_id: buyer.id, customer_part_number: "MY-BOLT", item:)
    end
  end

  def actor_of(tenant, role: "member")
    Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role:, partner_code: "")
  end

  def place(supplier_tenant_id: supplier.id, lines: [ { partNumber: "MY-BOLT", quantity: 10 } ], **input)
    graphql_body(<<~GRAPHQL, input: { supplierTenantId: supplier_tenant_id, lines:, **input }).fetch("data").fetch("placePurchaseOrder")
      mutation($input: PlacePurchaseOrderInput!) {
        placePurchaseOrder(input: $input) {
          purchaseOrder { id orderNo status supplier { name } desiredDeliveryOn lines { partNumber quantity } }
          errors { code message path }
        }
      }
    GRAPHQL
  end

  def purchase_order(id)
    graphql_body(<<~GRAPHQL, id:).dig("data", "buyer", "purchaseOrder")
      query($id: ID!) {
        buyer { purchaseOrder(id: $id) { status lines { partNumber confirmedItemName confirmedUnitPrice } } }
      }
    GRAPHQL
  end

  def sales_orders
    graphql_body(<<~GRAPHQL).dig("data", "supplier", "salesOrders", "nodes")
      {
        supplier {
          salesOrders {
            nodes {
              orderNo status customer { name } dueDate
              lines { customerPartNumber item { code } itemName unitPrice taxRatePercent quantity allocatedQuantity }
            }
          }
        }
      }
    GRAPHQL
  end

  # パッケージの中のモデルを参照せず、テナントの名義で表を直接読む
  def select_values(tenant, sql)
    Tenancy.with_tenant(tenant.id) { ActiveRecord::Base.lease_connection.select_values(sql) }
  end

  def sales_order_count
    [ select_values(supplier, "SELECT count(*) FROM sales_orders"), select_values(supplier, "SELECT count(*) FROM sales_order_lines") ]
      .map(&:sole)
  end

  it "発注 → イベントを流す → 受注確定 → 発注が「受注済」になり、確定した品目名と単価が写る" do
    login_as(buyer_member)
    placed = place(desiredDeliveryOn: "2026-11-02")
    expect(placed).to match("purchaseOrder" => include("orderNo" => "PO-000001", "status" => "SENT",
      "supplier" => { "name" => "青嵐精機工業" }, "desiredDeliveryOn" => "2026-11-02",
      "lines" => [ { "partNumber" => "MY-BOLT", "quantity" => 10 } ]), "errors" => [])
    # 受注はイベントが届くまで作られない
    expect(sales_order_count).to eq([ 0, 0 ])

    deliver_enqueued_events

    login_as(supplier_member)
    expect(sales_orders).to eq([ {
      "orderNo" => "SO-000001", "status" => "RECEIVED", "customer" => { "name" => "組立メーカー" }, "dueDate" => "2026-11-02",
      "lines" => [ { "customerPartNumber" => "MY-BOLT", "item" => { "code" => "BOLT-8" }, "itemName" => "六角ボルト M8",
        "unitPrice" => "120", "taxRatePercent" => 10, "quantity" => 10, "allocatedQuantity" => 0 } ]
    } ])

    login_as(buyer_member)
    expect(purchase_order(placed.dig("purchaseOrder", "id"))).to eq("status" => "ACCEPTED",
      "lines" => [ { "partNumber" => "MY-BOLT", "confirmedItemName" => "六角ボルト M8", "confirmedUnitPrice" => "120" } ])
  end

  # 照合の分岐は Sales::PurchaseOrderTranslator の spec が確かめる。ここでは「品番照合待ち」が購買の受け手まで届くことを確かめる
  it "照合できない明細があれば、「品番照合待ち」が発注側に届き、発注は「受注側で確認中」になる" do
    login_as(buyer_member)
    placed = place(lines: [ { partNumber: "MY-BOLT", quantity: 1 }, { partNumber: "UNKNOWN", quantity: 2 } ])
    deliver_enqueued_events

    expect(purchase_order(placed.dig("purchaseOrder", "id"))).to eq("status" => "AWAITING_SUPPLIER_CONFIRMATION",
      "lines" => [ { "partNumber" => "MY-BOLT", "confirmedItemName" => nil, "confirmedUnitPrice" => nil },
        { "partNumber" => "UNKNOWN", "confirmedItemName" => nil, "confirmedUnitPrice" => nil } ])
  end

  # 相手の種類ごとの NOT_PERMITTED は Purchasing::Ordering の spec が確かめる。ここでは失敗がユーザーエラーに写ることと、
  # 失効の前の発注がイベントで受注まで進むことを確かめる
  it "取引関係を失効させると新しい発注は NOT_PERMITTED のユーザーエラーになるが、失効の前に出した発注は受注まで進む" do
    login_as(buyer_member)
    placed = place

    Tenancy.with_tenant(supplier.id) { Partnerships::Management.revoke(actor_of(supplier, role: "admin"), partnership_id: partnership.id) }
    expect(place).to eq("purchaseOrder" => nil,
      "errors" => [ { "code" => "NOT_PERMITTED", "message" => "Not permitted", "path" => [ "supplierTenantId" ] } ])

    deliver_enqueued_events
    expect(purchase_order(placed.dig("purchaseOrder", "id"))).to include("status" => "ACCEPTED")
  end

  # 明細の誤りの分岐と上限は Purchasing::Ordering の spec が確かめる
  it "明細の誤りを、入れ子の項目を指す INVALID_INPUT のユーザーエラーで返す" do
    login_as(buyer_member)

    expect(place(lines: [ { partNumber: "A", quantity: 0 } ])["errors"])
      .to match([ include("code" => "INVALID_INPUT", "path" => [ "lines", "0", "quantity" ]) ])
  end

  # 一覧を別のコンテキストの値（受注側の名前）と合計で並べる（docs/architecture/graphql-schema.md「ページングと N+1」）
  describe "発注の一覧の並べ替えと合計" do
    # 引数の検証のエラーなら nodes は無く、nil を返す
    def purchase_orders(order_by, fields)
      graphql_body(<<~GRAPHQL, orderBy: order_by).dig("data", "buyer", "purchaseOrders", "nodes")
        query($orderBy: PurchaseOrderOrder) { buyer { purchaseOrders(orderBy: $orderBy) { nodes { orderNo #{fields} } } } }
      GRAPHQL
    end

    # lines は明細ごとの [数量, 確定した単価]。単価が nil の明細は受注確定の前
    def order(order_no, supplier_tenant, lines)
      Tenancy.with_tenant(buyer.id) do
        FactoryBot.create(:purchase_order, order_no:, supplier_tenant_id: supplier_tenant.id).tap do |order|
          lines.each do |quantity, price|
            FactoryBot.create(:purchase_order_line, purchase_order: order, quantity:, confirmed_unit_price: price,
              confirmed_item_name: price && "六角ボルト M8")
          end
        end
      end
    end

    it "受注側の名前の順に並べる" do
      other = FactoryBot.create(:tenant, name: "あおば製作所")
      order("PO-000001", supplier, [ [ 1, 120 ] ])
      order("PO-000002", other, [ [ 1, 120 ] ])
      order("PO-000003", supplier, [ [ 1, 120 ] ])
      login_as(buyer_member)

      expect(purchase_orders({ field: "SUPPLIER_NAME", direction: "ASC" }, "supplier { name }"))
        .to eq([ { "orderNo" => "PO-000002", "supplier" => { "name" => "あおば製作所" } },
          { "orderNo" => "PO-000001", "supplier" => { "name" => "青嵐精機工業" } },
          { "orderNo" => "PO-000003", "supplier" => { "name" => "青嵐精機工業" } } ])
    end

    # 名前の列の照合順序 ja-x-icu は、漢字を音読みの順（青嵐のセイが東和のトウより前）で並べ、流用元の Intl.Collator("ja") と
    # 同じ並びになる。コードポイントの順では東和商事が先になる。ページの境目のカーソルも同じ照合順序で比べる
    it "受注側の名前を、漢字の音読みの順に 1 件ずつのページで並べる" do
      other = FactoryBot.create(:tenant, name: "東和商事")
      order("PO-000001", other, [ [ 1, 120 ] ])
      order("PO-000002", supplier, [ [ 1, 120 ] ])
      login_as(buyer_member)
      query = <<~GRAPHQL
        query($after: String) {
          buyer { purchaseOrders(first: 1, after: $after, orderBy: { field: SUPPLIER_NAME, direction: ASC }) {
            nodes { orderNo supplier { name } } pageInfo { hasNextPage endCursor }
          } }
        }
      GRAPHQL

      first = graphql_body(query).dig("data", "buyer", "purchaseOrders")
      expect(first.fetch("nodes")).to eq([ { "orderNo" => "PO-000002", "supplier" => { "name" => "青嵐精機工業" } } ])
      expect(first.dig("pageInfo", "hasNextPage")).to be(true)
      second = graphql_body(query, after: first.dig("pageInfo", "endCursor")).dig("data", "buyer", "purchaseOrders")
      expect(second.fetch("nodes")).to eq([ { "orderNo" => "PO-000001", "supplier" => { "name" => "東和商事" } } ])
      expect(second.dig("pageInfo", "hasNextPage")).to be(false)
    end

    it "bigint の上限を超える合計を 10 進の文字列で返し、受注確定の前の明細を含む発注の合計は空にする" do
      order("PO-000001", supplier, [ [ 3, 2**63 - 1 ] ])
      order("PO-000002", supplier, [ [ 1, nil ] ])
      login_as(buyer_member)

      expect(purchase_orders({ field: "TOTAL_AMOUNT", direction: "DESC" }, "totalAmount"))
        .to eq([ { "orderNo" => "PO-000001", "totalAmount" => "27670116110564327421" }, { "orderNo" => "PO-000002", "totalAmount" => nil } ])
    end
  end

  describe "連結の冪等性" do
    context "受注側の ACL" do
      let!(:placed) do
        Tenancy.with_tenant(buyer.id) do
          Purchasing::Ordering.place(buyer_actor, supplier_tenant_id: supplier.id,
            lines: [ { part_number: "MY-BOLT", quantity: 1 }, { part_number: "UNKNOWN", quantity: 1 } ]).value
        end
      end

      # 発注が出したものと同じ「発注登録」をもう一度出す
      let(:replayed_event) do
        lines = Tenancy.with_tenant(buyer.id) { Purchasing::PurchaseOrders.lines_for(buyer_actor, [ placed.id ]).fetch(placed.id) }
        Contracts::PurchaseOrderPlaced.new(purchase_order_id: placed.id, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id,
          desired_delivery_on: nil,
          lines: lines.map { { "purchase_order_line_id" => _1.id, "part_number" => _1.part_number, "quantity" => _1.quantity } })
      end

      it_behaves_like "冪等な受け手" do
        let(:publish_event) { -> { Tenancy.with_tenant(buyer.id) { Contracts.publish(replayed_event) } } }
        let(:written_rows) { -> { sales_order_count.sum } }
      end
    end

    it "購買の受け手は、2 回目の「受注確定」で発注明細の写しも受注済の時刻も書き換えない" do
      placed = Tenancy.with_tenant(buyer.id) do
        Purchasing::Ordering.place(buyer_actor, supplier_tenant_id: supplier.id, lines: [ { part_number: "MY-BOLT", quantity: 1 } ]).value
      end
      deliver_enqueued_events
      read = lambda do
        [ select_values(buyer, "SELECT accepted_at FROM purchase_orders"), select_values(buyer, "SELECT confirmed_item_name FROM purchase_order_lines") ]
      end
      first = read.call

      line_id = select_values(buyer, "SELECT id FROM purchase_order_lines").sole
      Tenancy.with_tenant(supplier.id) do
        Contracts.publish(Contracts::SalesOrderConfirmed.new(purchase_order_id: placed.id, buyer_tenant_id: buyer.id,
          supplier_tenant_id: supplier.id, lines: [ { "purchase_order_line_id" => line_id, "item_name" => "別名", "unit_price" => "1" } ]))
      end
      deliver_enqueued_events(times: 2)

      expect(read.call).to eq(first)
      expect(first.last).to eq([ "六角ボルト M8" ])
    end
  end
end
