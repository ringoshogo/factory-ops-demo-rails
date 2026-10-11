# 入口の行列の期待値。視点の入口と Mutation のフィールドはすべてここに行を持つ。
# 行の無いフィールドがあれば spec/matrix/graphql_matrix_spec.rb が落ちる
module MatrixExpectations
  # 値が返る・空の一覧・null・ユーザーエラーの NOT_FOUND と NOT_PERMITTED・トップレベルのエラーの FORBIDDEN
  # （docs/architecture/graphql-schema.md「エラー」）
  OUTCOMES = %i[value empty null not_found not_permitted forbidden].freeze

  # "型.フィールド" => { query:, variables: ->(world) { ... }（省略可）, role:（mutation だけ）, expect: { ペルソナ => 結果 } }。
  # query は対象のフィールドを 1 つだけ選ぶ。variables は世界の行の ID を引数に渡すときに書く。
  # role は mutation を許す役割（:admin か :member）で、docs/architecture/graphql-schema.md「役割による制限」の表に合わせる。
  # expect はペルソナの admin で呼んだ結果である
  # 世界の各ペルソナは、自社が受注側の取引関係を factory で 1 件ずつ持つ（相手は世界の外のテナント）
  EVERYONE = MatrixWorld::PERSONAS.index_with(:value).freeze
  # supplier の行を対象にする mutation。相手のペルソナからは見えない ID なので NOT_FOUND になる
  ONLY_SUPPLIER = MatrixWorld::PERSONAS.index_with(:not_found).merge(supplier: :value).freeze

  PARTNERSHIP_MUTATION = "{ partnership { id } errors { code } }".freeze
  ITEM_MUTATION = "{ item { id } errors { code } }".freeze
  SHIPMENT_REQUEST_MUTATION = "{ shipmentRequest { id } errors { code } }".freeze

  # ID で 1 件を引く入口。持ち主のペルソナにだけ値が返り、他のペルソナには存在しない ID と同じ null になる
  def self.only(persona) = MatrixWorld::PERSONAS.index_with(:null).merge(persona => :value).freeze

  GRAPHQL = {
    "Query.viewer" => {
      query: "{ viewer { id } }",
      expect: EVERYONE
    },
    # 自社の監査ログ。世界のペルソナは admin で、どのペルソナにも自社の行だけが返る
    "Viewer.auditLogs" => {
      query: "{ viewer { auditLogs { nodes { action } } } }",
      expect: EVERYONE
    },
    "SupplierView.partnerships" => {
      query: "{ supplier { partnerships { id } } }",
      expect: EVERYONE
    },
    # 経路 2。有効な取引関係があれば権限付与が無くても開き、失効で閉じる
    "BuyerView.suppliers" => {
      query: "{ buyer { suppliers { supplier { name } } } }",
      expect: { supplier: :empty, granted_buyer: :value, ungranted_buyer: :value, revoked_buyer: :empty, stranger: :empty }
    },
    # 経路 2 の取引先を 1 社選ぶ。supplier の取引先の関係を、発注側の各ペルソナから引く
    "BuyerView.supplier" => {
      query: "query($id: ID!) { buyer { supplier(supplierTenantId: $id) { supplier { name } } } }",
      variables: ->(world) { { id: world.tenants[:supplier] } },
      expect: { supplier: :null, granted_buyer: :value, ungranted_buyer: :value, revoked_buyer: :null, stranger: :null }
    },
    "SupplierView.items" => {
      query: "{ supplier { items { nodes { id } } } }",
      expect: EVERYONE
    },
    # 経路 1。有効な取引関係と view_catalog の付与がある発注側にだけ開き、付与があっても失効で閉じる
    "SupplierPartnership.catalog" => {
      query: "{ buyer { suppliers { catalog { nodes { code } } } } }",
      expect: { supplier: :empty, granted_buyer: :value, ungranted_buyer: :empty, revoked_buyer: :empty, stranger: :empty }
    },
    "Mutation.establishPartnership" => {
      role: :admin,
      query: "mutation($input: EstablishPartnershipInput!) { establishPartnership(input: $input) #{PARTNERSHIP_MUTATION} }",
      # 世界の外の新しいテナントと結ぶ。create_tenant は取引用コードを "p-<code>" にする
      variables: ->(world) { world.create_tenant("newcomer") && { input: { partnerCode: "p-newcomer" } } },
      expect: EVERYONE
    },
    "Mutation.revokePartnership" => {
      role: :admin,
      query: "mutation($input: RevokePartnershipInput!) { revokePartnership(input: $input) #{PARTNERSHIP_MUTATION} }",
      variables: ->(world) { { input: { partnershipId: world.partnership(:granted_buyer).id } } },
      expect: ONLY_SUPPLIER
    },
    "Mutation.grantPermission" => {
      role: :admin,
      query: "mutation($input: GrantPermissionInput!) { grantPermission(input: $input) #{PARTNERSHIP_MUTATION} }",
      variables: ->(world) { { input: { partnershipId: world.partnership(:ungranted_buyer).id, permission: "VIEW_CATALOG" } } },
      expect: ONLY_SUPPLIER
    },
    "Mutation.withdrawPermission" => {
      role: :admin,
      query: "mutation($input: WithdrawPermissionInput!) { withdrawPermission(input: $input) #{PARTNERSHIP_MUTATION} }",
      variables: ->(world) { { input: { partnershipId: world.partnership(:granted_buyer).id, permission: "VIEW_CATALOG" } } },
      expect: ONLY_SUPPLIER
    },
    "Mutation.saveItem" => {
      role: :member,
      query: "mutation($input: SaveItemInput!) { saveItem(input: $input) #{ITEM_MUTATION} }",
      variables: ->(_world) { { input: { code: "NEW-1", name: "新しい品目", unit: "個", unitPrice: 100 } } },
      expect: EVERYONE
    },
    "Mutation.setItemPublished" => {
      role: :member,
      query: "mutation($input: SetItemPublishedInput!) { setItemPublished(input: $input) #{ITEM_MUTATION} }",
      variables: ->(world) { { input: { itemId: world.row("items", :supplier).id, published: true } } },
      expect: ONLY_SUPPLIER
    },
    # 対応表は受注側だけが所有する。どのペルソナにも自社の行だけが返る
    "SupplierView.partMappings" => {
      query: "{ supplier { partMappings { nodes { id } } } }",
      expect: EVERYONE
    },
    # supplier の品目を、supplier の取引先（granted_buyer）の品番に対応させる
    "Mutation.registerPartMapping" => {
      role: :member,
      query: "mutation($input: RegisterPartMappingInput!) { registerPartMapping(input: $input) { partMapping { id } errors { code } } }",
      variables: lambda { |world|
        { input: { customerTenantId: world.tenants[:granted_buyer], customerPartNumber: "NEW-PART",
          itemId: world.row("items", :supplier).id } }
      },
      expect: ONLY_SUPPLIER
    },
    "BuyerView.purchaseOrders" => {
      query: "{ buyer { purchaseOrders { nodes { id } } } }",
      expect: EVERYONE
    },
    # 経路 3。自社の発注に連結した出荷が、有効な取引関係と view_shipments の付与がある発注側にだけ見え、
    # 付与があっても失効で閉じる。受注側の supplier の発注には連結した出荷が無い
    "PurchaseOrder.supplierShipments" => {
      query: "{ buyer { purchaseOrders { nodes { supplierShipments { shippedOn } } } } }",
      expect: { supplier: :empty, granted_buyer: :value, ungranted_buyer: :empty, revoked_buyer: :empty, stranger: :empty }
    },
    # 連結した受注を持つ発注。受注側の supplier にも見えない
    "BuyerView.purchaseOrder" => {
      query: "query($id: ID!) { buyer { purchaseOrder(id: $id) { id } } }",
      variables: ->(world) { { id: world.linked_order(:purchase_order).id } },
      expect: only(:granted_buyer)
    },
    "SupplierView.salesOrders" => {
      query: "{ supplier { salesOrders { nodes { id } } } }",
      expect: EVERYONE
    },
    # 発注に連結した受注。発注側の granted_buyer にも見えない
    "SupplierView.salesOrder" => {
      query: "query($id: ID!) { supplier { salesOrder(id: $id) { id } } }",
      variables: ->(world) { { id: world.linked_order(:sales_order).id } },
      expect: only(:supplier)
    },
    # 在庫は受注側だけが所有する。どのペルソナにも自社の行だけが返る
    "SupplierView.stocks" => {
      query: "{ supplier { stocks { nodes { onHand } } } }",
      expect: EVERYONE
    },
    "SupplierView.stockMovements" => {
      query: "{ supplier { stockMovements { nodes { id } } } }",
      expect: EVERYONE
    },
    "Mutation.adjustStock" => {
      role: :member,
      query: "mutation($input: AdjustStockInput!) { adjustStock(input: $input) { stock { onHand } errors { code } } }",
      variables: ->(world) { { input: { itemId: world.row("items", :supplier).id, type: "INBOUND", quantity: 1 } } },
      expect: ONLY_SUPPLIER
    },
    # 発注に連結した受注。有効在庫が無くても、引当の操作そのものは成功する
    "Mutation.allocateSalesOrder" => {
      role: :member,
      query: "mutation($input: AllocateSalesOrderInput!) { allocateSalesOrder(input: $input) { salesOrder { id } errors { code } } }",
      variables: ->(world) { { input: { salesOrderId: world.linked_order(:sales_order).id } } },
      expect: ONLY_SUPPLIER
    },
    # 出荷は受注側だけが所有する。どのペルソナにも自社の行だけが返る
    "SupplierView.shipmentRequests" => {
      query: "{ supplier { shipmentRequests { nodes { id } } } }",
      expect: EVERYONE
    },
    # 出荷指示の無い出荷依頼に指示を作る
    "Mutation.createShippingInstruction" => {
      role: :member,
      query: "mutation($input: CreateShippingInstructionInput!) { createShippingInstruction(input: $input) #{SHIPMENT_REQUEST_MUTATION} }",
      variables: lambda { |world|
        { input: { shipmentRequestId: world.row("shipment_requests", :supplier).id, plannedDate: Date.current.iso8601 } }
      },
      expect: ONLY_SUPPLIER
    },
    "Mutation.cancelShippingInstruction" => {
      role: :member,
      query: "mutation($input: CancelShippingInstructionInput!) { cancelShippingInstruction(input: $input) #{SHIPMENT_REQUEST_MUTATION} }",
      variables: ->(world) { { input: { shipmentRequestId: world.row("shipping_instructions", :supplier).shipment_request_id } } },
      expect: ONLY_SUPPLIER
    },
    # 有効な指示のある出荷依頼に、active の引当を持つ明細を 1 つ足して計上する
    "Mutation.postShipment" => {
      role: :member,
      query: "mutation($input: PostShipmentInput!) { postShipment(input: $input) #{SHIPMENT_REQUEST_MUTATION} }",
      variables: lambda { |world|
        request = world.row("shipping_instructions", :supplier).shipment_request
        world.as(:supplier) do
          allocation = FactoryBot.create(:allocation)
          FactoryBot.create(:shipment_request_line, shipment_request: request, sales_order_line_id: allocation.sales_order_line_id,
            item_id: allocation.item_id, quantity: allocation.quantity)
        end
        { input: { shipmentRequestId: request.id, shippedOn: Date.current.iso8601 } }
      },
      expect: ONLY_SUPPLIER
    },
    # 連結した受注を持つ発注への取消依頼。発注を所有する granted_buyer だけが依頼でき、受注側の supplier にも見えない
    "Mutation.requestPurchaseOrderCancellation" => {
      role: :admin,
      query: "mutation($input: RequestPurchaseOrderCancellationInput!) { requestPurchaseOrderCancellation(input: $input) { purchaseOrder { id } errors { code } } }",
      variables: ->(world) { { input: { purchaseOrderId: world.linked_order(:purchase_order).id, reason: "数量の誤り" } } },
      expect: MatrixWorld::PERSONAS.index_with(:not_found).merge(granted_buyer: :value)
    },
    # 検収前の入荷の全明細を出荷数量で検収する。入荷を所有する granted_buyer だけが検収でき、受注側の supplier にも見えない
    "Mutation.inspectInboundShipment" => {
      role: :admin,
      query: "mutation($input: InspectInboundShipmentInput!) { inspectInboundShipment(input: $input) { purchaseOrder { id } errors { code } } }",
      variables: lambda { |world|
        line = world.row("inbound_shipment_lines", :granted_buyer)
        { input: { inboundShipmentId: line.inbound_shipment_id,
                   lines: [ { inboundShipmentLineId: line.id, acceptedQuantity: line.shipped_quantity } ] } }
      },
      expect: MatrixWorld::PERSONAS.index_with(:not_found).merge(granted_buyer: :value)
    },
    # 発注に連結した受注。受注側の supplier だけが取り消せる
    "Mutation.cancelSalesOrder" => {
      role: :admin,
      query: "mutation($input: CancelSalesOrderInput!) { cancelSalesOrder(input: $input) { salesOrder { id } errors { code } } }",
      variables: ->(world) { { input: { salesOrderId: world.linked_order(:sales_order).id } } },
      expect: ONLY_SUPPLIER
    },
    # supplier の審査中の審査。発注側のペルソナには、相手の受注の審査は見えない
    "Mutation.approveCancellationReview" => {
      role: :admin,
      query: "mutation($input: ApproveCancellationReviewInput!) { approveCancellationReview(input: $input) { salesOrder { id } errors { code } } }",
      variables: ->(world) { { input: { cancellationReviewId: world.row("cancellation_reviews", :supplier).id } } },
      expect: ONLY_SUPPLIER
    },
    "Mutation.rejectCancellationReview" => {
      role: :admin,
      query: "mutation($input: RejectCancellationReviewInput!) { rejectCancellationReview(input: $input) { salesOrder { id } errors { code } } }",
      variables: ->(world) { { input: { cancellationReviewId: world.row("cancellation_reviews", :supplier).id } } },
      expect: ONLY_SUPPLIER
    },
    # 請求は受注側だけが所有する。どのペルソナにも自社の行だけが返る
    "SupplierView.billingTerms" => {
      query: "{ supplier { billingTerms { closingDay } } }",
      expect: EVERYONE
    },
    "SupplierView.billableItems" => {
      query: "{ supplier { billableItems { nodes { id } } } }",
      expect: EVERYONE
    },
    "SupplierView.invoices" => {
      query: "{ supplier { invoices { nodes { id } } } }",
      expect: EVERYONE
    },
    "SupplierView.invoice" => {
      query: "query($id: ID!) { supplier { invoice(id: $id) { id } } }",
      variables: ->(world) { { id: world.row("invoices", :supplier).id } },
      expect: only(:supplier)
    },
    # supplier の取引先（granted_buyer）の請求条件。ほかのペルソナには取引先でないので NOT_FOUND になる
    "Mutation.setBillingTerm" => {
      role: :admin,
      query: "mutation($input: SetBillingTermInput!) { setBillingTerm(input: $input) { billingTerm { closingDay } errors { code } } }",
      variables: ->(world) { { input: { customerTenantId: world.tenants[:granted_buyer], closingDay: 20 } } },
      expect: ONLY_SUPPLIER
    },
    # supplier の取引先（granted_buyer）に月末締めの請求条件と、今日検収した未請求明細を足して締める
    "Mutation.closeBillingPeriod" => {
      role: :admin,
      query: "mutation($input: CloseBillingPeriodInput!) { closeBillingPeriod(input: $input) { invoice { id } errors { code } } }",
      variables: lambda { |world|
        world.as(:supplier) do
          FactoryBot.create(:billing_term, customer_tenant_id: world.tenants[:granted_buyer], closing_day: 31)
          FactoryBot.create(:billable_item, customer_tenant_id: world.tenants[:granted_buyer])
        end
        { input: { customerTenantId: world.tenants[:granted_buyer], closingDate: Date.current.end_of_month.iso8601 } }
      },
      expect: ONLY_SUPPLIER
    },
    # supplier の下書きの請求書
    "Mutation.discardDraftInvoice" => {
      role: :admin,
      query: "mutation($input: DiscardDraftInvoiceInput!) { discardDraftInvoice(input: $input) { discardedInvoiceId errors { code } } }",
      variables: ->(world) { { input: { invoiceId: world.row("invoices", :supplier).id } } },
      expect: ONLY_SUPPLIER
    },
    "Mutation.issueInvoice" => {
      role: :admin,
      query: "mutation($input: IssueInvoiceInput!) { issueInvoice(input: $input) { invoice { id } errors { code } } }",
      variables: ->(world) { { input: { invoiceId: world.row("invoices", :supplier).id } } },
      expect: ONLY_SUPPLIER
    },
    # 受領請求書は発注側だけが所有する。どのペルソナにも自社の行だけが返る
    "BuyerView.receivedInvoices" => {
      query: "{ buyer { receivedInvoices { nodes { id } } } }",
      expect: EVERYONE
    },
    "BuyerView.receivedInvoice" => {
      query: "query($id: ID!) { buyer { receivedInvoice(id: $id) { id } } }",
      variables: ->(world) { { id: world.row("received_invoices", :granted_buyer).id } },
      expect: only(:granted_buyer)
    },
    # supplier への発注。place_orders の付与がある有効な取引関係の発注側だけが登録でき、
    # 付与の無い・失効した・関係の無い相手と自分自身への発注は、どれも同じ NOT_PERMITTED になる
    "Mutation.placePurchaseOrder" => {
      role: :member,
      query: "mutation($input: PlacePurchaseOrderInput!) { placePurchaseOrder(input: $input) { purchaseOrder { id } errors { code } } }",
      variables: ->(world) { { input: { supplierTenantId: world.tenants[:supplier], lines: [ { partNumber: "P-1", quantity: 1 } ] } } },
      expect: MatrixWorld::PERSONAS.index_with(:not_permitted).merge(granted_buyer: :value)
    }
  }.freeze
end
