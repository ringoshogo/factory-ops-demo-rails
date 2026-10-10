require "rails_helper"
require_relative "../support/scenarios"

# テナントの境界（docs/guides/testing.md「重要シナリオ」S1）。発注側が、イベントで受け取った相手の ID と、受注側の伝票の ID を、
# ID を取るすべての入口に持ち込んでも、相手のデータに届かない。入口は FactoryOpsSchema を走査して集め、
# 下の表に無い入口があれば落ちる（docs/architecture/graphql-schema.md「ID と `node`」）
RSpec.describe "テナントの境界", type: :request do
  # 受注側の伝票の ID と、イベントで受け取った出荷実績・受注・受注明細の ID
  documents = %i[shipment sales_order sales_order_line shipment_request item partnership cancellation_review invoice]
  not_found = { "errors" => [ { "code" => "NOT_FOUND" } ] }

  # 入口（型.フィールド(引数の道)）ごとに、相手の ID を入れる引数と、入れる ID の種類と、届かないときの結果。
  # run は相手の ID を受け取って入口を呼び、結果を返す。ほかの引数には発注側の自社の正しい値を入れる
  boundary = {
    "BuyerView.purchaseOrder(id)" => {
      ids: documents, reach: nil,
      run: ->(id) { query("query($id: ID!) { buyer { purchaseOrder(id: $id) { id } } }", id:).dig("buyer", "purchaseOrder") }
    },
    # 取引関係の無い相手と、自社のテナントは、存在しないテナントと同じ null になる
    "BuyerView.supplier(supplierTenantId)" => {
      ids: [ *documents, :buyer_tenant, :outsider_tenant ], reach: nil,
      run: lambda do |id|
        query("query($id: ID!) { buyer { supplier(supplierTenantId: $id) { supplier { id } } } }", id:).dig("buyer", "supplier")
      end
    },
    "SupplierView.salesOrder(id)" => {
      ids: documents, reach: nil,
      run: ->(id) { query("query($id: ID!) { supplier { salesOrder(id: $id) { id } } }", id:).dig("supplier", "salesOrder") }
    },
    "SupplierView.stockMovements(itemId)" => {
      ids: documents, reach: [],
      run: lambda do |id|
        query("query($id: ID) { supplier { stockMovements(itemId: $id) { nodes { id } } } }", id:).dig("supplier", "stockMovements", "nodes")
      end
    },
    # 相手の対応表は、発注側のテナントを得意先にしている
    "SupplierView.partMappings(customerTenantId)" => {
      ids: %i[supplier_tenant buyer_tenant], reach: [],
      run: lambda do |id|
        query("query($id: ID) { supplier { partMappings(customerTenantId: $id) { nodes { id } } } }", id:)
          .dig("supplier", "partMappings", "nodes")
      end
    },
    "SupplierView.invoice(id)" => {
      ids: documents, reach: nil,
      run: ->(id) { query("query($id: ID!) { supplier { invoice(id: $id) { id } } }", id:).dig("supplier", "invoice") }
    },
    # 相手の請求対象明細は、発注側のテナントを取引先にしている
    "SupplierView.billableItems(customerTenantId)" => {
      ids: %i[supplier_tenant buyer_tenant], reach: [],
      run: lambda do |id|
        query("query($id: ID) { supplier { billableItems(customerTenantId: $id) { nodes { id } } } }", id:)
          .dig("supplier", "billableItems", "nodes")
      end
    },
    "Mutation.setBillingTerm(input.customerTenantId)" => {
      ids: %i[supplier_tenant outsider_tenant], reach: not_found,
      run: ->(id) { mutate("setBillingTerm", customerTenantId: id, closingDay: 31) }
    },
    "Mutation.closeBillingPeriod(input.customerTenantId)" => {
      ids: %i[supplier_tenant outsider_tenant], reach: not_found,
      run: ->(id) { mutate("closeBillingPeriod", customerTenantId: id, closingDate: Date.current.end_of_month.iso8601) }
    },
    "Mutation.discardDraftInvoice(input.invoiceId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("discardDraftInvoice", invoiceId: id) }
    },
    "Mutation.adjustStock(input.itemId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("adjustStock", itemId: id, type: "INBOUND", quantity: 1) }
    },
    "Mutation.allocateSalesOrder(input.salesOrderId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("allocateSalesOrder", salesOrderId: id) }
    },
    "Mutation.cancelSalesOrder(input.salesOrderId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("cancelSalesOrder", salesOrderId: id) }
    },
    "Mutation.createShippingInstruction(input.shipmentRequestId)" => {
      ids: documents, reach: not_found,
      run: ->(id) { mutate("createShippingInstruction", shipmentRequestId: id, plannedDate: "2026-10-20") }
    },
    "Mutation.cancelShippingInstruction(input.shipmentRequestId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("cancelShippingInstruction", shipmentRequestId: id) }
    },
    "Mutation.postShipment(input.shipmentRequestId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("postShipment", shipmentRequestId: id, shippedOn: "2026-10-20") }
    },
    "Mutation.grantPermission(input.partnershipId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("grantPermission", partnershipId: id, permission: "VIEW_CATALOG") }
    },
    "Mutation.withdrawPermission(input.partnershipId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("withdrawPermission", partnershipId: id, permission: "PLACE_ORDERS") }
    },
    "Mutation.revokePartnership(input.partnershipId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("revokePartnership", partnershipId: id) }
    },
    "Mutation.setItemPublished(input.itemId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("setItemPublished", itemId: id, published: true) }
    },
    "Mutation.registerPartMapping(input.itemId)" => {
      ids: documents, reach: not_found,
      run: ->(id) { mutate("registerPartMapping", customerTenantId: own_customer.id, customerPartNumber: "MY-BOLT", itemId: id) }
    },
    "Mutation.registerPartMapping(input.customerTenantId)" => {
      ids: %i[supplier_tenant outsider_tenant], reach: not_found,
      run: ->(id) { mutate("registerPartMapping", customerTenantId: id, customerPartNumber: "MY-BOLT", itemId: own_item_id) }
    },
    "Mutation.requestPurchaseOrderCancellation(input.purchaseOrderId)" => {
      ids: documents, reach: not_found,
      run: ->(id) { mutate("requestPurchaseOrderCancellation", purchaseOrderId: id, reason: "数量の誤り") }
    },
    "Mutation.inspectInboundShipment(input.inboundShipmentId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("inspectInboundShipment", inboundShipmentId: id, lines: []) }
    },
    # 自社の入荷に相手の ID を明細として入れる。入荷の明細でない ID は、別の入荷の明細と同じ INVALID_INPUT になる
    "Mutation.inspectInboundShipment(input.lines.inboundShipmentLineId)" => {
      ids: documents, reach: { "errors" => [ { "code" => "INVALID_INPUT" } ] },
      run: ->(id) { mutate("inspectInboundShipment", inboundShipmentId: own_inbound_id, lines: [ { inboundShipmentLineId: id, acceptedQuantity: 1 } ]) }
    },
    "Mutation.approveCancellationReview(input.cancellationReviewId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("approveCancellationReview", cancellationReviewId: id) }
    },
    "Mutation.rejectCancellationReview(input.cancellationReviewId)" => {
      ids: documents, reach: not_found, run: ->(id) { mutate("rejectCancellationReview", cancellationReviewId: id) }
    },
    # 発注は、存在しない・関係の無い・失効した・付与の無い相手を区別せず NOT_PERMITTED にする
    # （docs/architecture/graphql-schema.md「ID と `node`」）
    "Mutation.placePurchaseOrder(input.supplierTenantId)" => {
      ids: %i[outsider_tenant], reach: { "errors" => [ { "code" => "NOT_PERMITTED" } ] },
      run: ->(id) { mutate("placePurchaseOrder", supplierTenantId: id, lines: [ { partNumber: "MY-BOLT", quantity: 1 } ]) }
    }
  }

  # 引数（入力型の中の項目を含む）の型が ID の、引数の道を返す
  def self.id_argument_paths(arguments, prefix = [])
    arguments.flat_map do |name, argument|
      type = argument.type.unwrap
      if type.graphql_name == "ID" then [ [ *prefix, name ].join(".") ]
      elsif type.kind.input_object? then id_argument_paths(type.arguments, [ *prefix, name ])
      else []
      end
    end
  end

  def self.id_entries(schema)
    schema.types.values.select { |type| type.kind.object? && !type.introspection? }.flat_map do |type|
      type.fields.values.flat_map do |field|
        id_argument_paths(field.arguments).map { |path| "#{type.graphql_name}.#{field.name}(#{path})" }
      end
    end
  end

  it "ID を取る入口は、すべて表にある（入口を足したら、相手の ID を入れる行を表に足す）" do
    expect(self.class.id_entries(FactoryOpsSchema)).to match_array(boundary.keys)
  end

  let!(:supplier) { FactoryBot.create(:tenant, name: "青嵐精機工業") }
  let!(:buyer) { FactoryBot.create(:tenant, name: "組立メーカー") }
  # 発注側が受注側として取引する得意先と、どちらとも取引関係の無いテナント
  let!(:own_customer) { FactoryBot.create(:tenant) }
  let!(:outsider) { FactoryBot.create(:tenant) }
  let(:supplier_admin) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) } }
  let(:buyer_admin) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user, :admin) } }
  attr_reader :own_item_id, :own_inbound_id, :partner_ids

  describe "相手の ID を入口に持ち込む" do
    # 2 社が取引関係を結び、2 件の発注を発注 → 受注 → 引当 → 出荷指示 → 出荷計上まで進め、発注側に入荷を届ける。
    # 1 件目の入荷は検収せずに残し、2 件目は検収して、受注側が締めて下書きの請求書を作る。
    # 3 件目の発注には取消を依頼し、受注側に審査中の審査を作る。
    # 発注側は、自社が受注側の取引関係と品目も持つ
    before do
      login_as(supplier_admin)
      partnership_id = mutate!("establishPartnership", "partnership { id }", partnerCode: buyer.partner_code).dig("partnership", "id")
      mutate!("grantPermission", "partnership { id }", partnershipId: partnership_id, permission: "PLACE_ORDERS")
      item_id = mutate!("saveItem", "item { id }", code: "BOLT-8", name: "六角ボルト M8", unit: "本", unitPrice: "120").dig("item", "id")
      mutate!("registerPartMapping", "partMapping { id }", customerTenantId: buyer.id, customerPartNumber: "MY-BOLT", itemId: item_id)
      mutate!("adjustStock", "stock { onHand }", itemId: item_id, type: "INBOUND", quantity: 10)

      login_as(buyer_admin)
      purchase_order_id, billed_order_id = [ 4, 2 ].map do |quantity|
        mutate!("placePurchaseOrder", "purchaseOrder { id }",
          supplierTenantId: supplier.id, lines: [ { partNumber: "MY-BOLT", quantity: } ]).dig("purchaseOrder", "id")
      end
      deliver_enqueued_events

      login_as(supplier_admin)
      query("{ supplier { salesOrders { nodes { id } } } }").dig("supplier", "salesOrders", "nodes").each do |order|
        mutate!("allocateSalesOrder", "salesOrder { id }", salesOrderId: order.fetch("id"))
      end
      deliver_enqueued_events
      requests = query("{ supplier { shipmentRequests { nodes { id salesOrder { id } } } } }").dig("supplier", "shipmentRequests", "nodes")
      requests.each do |request|
        mutate!("createShippingInstruction", "shipmentRequest { id }", shipmentRequestId: request.fetch("id"), plannedDate: "2026-10-20")
        mutate!("postShipment", "shipmentRequest { id }", shipmentRequestId: request.fetch("id"), shippedOn: "2026-10-20")
      end
      posted = enqueued_payloads("Contracts::ShipmentPosted").find { _1.fetch("purchase_order_id") == purchase_order_id }
      request_id = requests.find { _1.dig("salesOrder", "id") == posted.fetch("sales_order_id") }.fetch("id")
      deliver_enqueued_events

      login_as(buyer_admin)
      inbound = query("query($id: ID!) { buyer { purchaseOrder(id: $id) { status inboundShipments { id } } } }", id: purchase_order_id)
      expect(inbound.dig("buyer", "purchaseOrder", "status")).to eq("INBOUND")
      @own_inbound_id = inbound.dig("buyer", "purchaseOrder", "inboundShipments").sole.fetch("id")
      billed = query("query($id: ID!) { buyer { purchaseOrder(id: $id) { inboundShipments { id lines { id shippedQuantity } } } } }",
        id: billed_order_id).dig("buyer", "purchaseOrder", "inboundShipments").sole
      mutate!("inspectInboundShipment", "purchaseOrder { id }", inboundShipmentId: billed.fetch("id"),
        lines: billed.fetch("lines").map { { inboundShipmentLineId: _1.fetch("id"), acceptedQuantity: _1.fetch("shippedQuantity") } })
      deliver_enqueued_events

      login_as(supplier_admin)
      mutate!("setBillingTerm", "billingTerm { closingDay }", customerTenantId: buyer.id, closingDay: 31)
      invoice_id = mutate!("closeBillingPeriod", "invoice { id }", customerTenantId: buyer.id,
        closingDate: Date.current.end_of_month.iso8601).dig("invoice", "id")

      login_as(buyer_admin)
      # 3 件目の発注に取消を依頼し、受注側に審査中の審査を作る
      cancelling_id = mutate!("placePurchaseOrder", "purchaseOrder { id }",
        supplierTenantId: supplier.id, lines: [ { partNumber: "MY-BOLT", quantity: 1 } ]).dig("purchaseOrder", "id")
      deliver_enqueued_events
      mutate!("requestPurchaseOrderCancellation", "purchaseOrder { id }", purchaseOrderId: cancelling_id, reason: "数量の誤り")
      deliver_enqueued_events
      login_as(supplier_admin)
      review_id = query("{ supplier { salesOrders { nodes { cancellationReviews { id } } } } }")
        .dig("supplier", "salesOrders", "nodes").flat_map { _1["cancellationReviews"] }.sole["id"]
      login_as(buyer_admin)
      mutate!("establishPartnership", "partnership { id }", partnerCode: own_customer.partner_code)
      @own_item_id = mutate!("saveItem", "item { id }", code: "OWN-1", name: "自社品目", unit: "個", unitPrice: "10").dig("item", "id")

      @partner_ids = {
        shipment: posted.fetch("shipment_id"), sales_order: posted.fetch("sales_order_id"),
        sales_order_line: posted.fetch("lines").sole.fetch("sales_order_line_id"), shipment_request: request_id, item: item_id,
        partnership: partnership_id, cancellation_review: review_id, invoice: invoice_id, supplier_tenant: supplier.id,
        buyer_tenant: buyer.id, outsider_tenant: outsider.id
      }
      expect(partner_ids.values).to all(be_present)
    end

    boundary.each do |entry, row|
      it "発注側のユーザーが #{entry} に相手の ID を入れても、相手のデータに届かない" do
        results = row.fetch(:ids).index_with { |kind| instance_exec(partner_ids.fetch(kind), &row.fetch(:run)) }

        expect(results).to eq(row.fetch(:ids).index_with { row.fetch(:reach) })
      end
    end
  end
end
