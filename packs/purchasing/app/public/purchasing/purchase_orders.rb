module Purchasing
  # 発注側が自社の発注を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）。
  # 状況と合計金額は、行と一緒に PurchaseOrderStatus と PurchaseOrderAmount の SQL の式で読む
  module PurchaseOrders
    # order_by は { field:, direction: } で、省けば作った順の新しいものから並べる。
    # filter は受注側と、両端を含む発注日の範囲と、状況で絞る。状況の空の配列は 0 件で、nil なら絞らない
    def self.list(actor, first:, after:, order_by: nil, filter: {})
      Page.of(filtered(Scope.call(actor, :own), **filter), first:, after:, sort: Page::Sort.of(order_by, order_columns(actor)),
        columns:) { to_values(_1) }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      to_values(with_status(Scope.call(actor, :own).where(id:))).first
    end

    # 発注 ID ごとの明細。見えない発注の ID は空の配列になる
    def self.lines_for(actor, order_ids)
      lines = PurchaseOrderLine.where(purchase_order_id: Scope.call(actor, :own).where(id: order_ids).select(:id)).order(:id)
      order_ids.index_with { [] }.merge(lines.map { to_line_value(_1) }.group_by(&:purchase_order_id))
    end

    # 明細 ID ごとの発注明細。経路 3 の出荷明細と入荷明細が、自社の発注明細を引くのに使う
    def self.lines_by_id(actor, line_ids)
      PurchaseOrderLine.where(id: line_ids, purchase_order_id: Scope.call(actor, :own).select(:id)).to_h { [ _1.id, to_line_value(_1) ] }
    end

    # 発注 ID ごとの取消依頼。古い順に並べる
    def self.cancellation_requests_for(actor, order_ids)
      requests = CancellationRequest.where(purchase_order_id: Scope.call(actor, :own).where(id: order_ids).select(:id)).order(:id)
      order_ids.index_with { [] }.merge(requests.map { to_cancellation_request_value(_1) }.group_by(&:purchase_order_id))
    end

    # 発注 ID ごとの入荷（「出荷計上」の写し）
    def self.inbound_shipments_for(actor, order_ids)
      shipments = InboundShipment.where(purchase_order_id: Scope.call(actor, :own).where(id: order_ids).select(:id)).order(:id)
      order_ids.index_with { [] }.merge(shipments.map { to_record_value(InboundShipmentValue, _1) }.group_by(&:purchase_order_id))
    end

    # 入荷 ID ごとの入荷明細。検収数量は検収の前は空
    def self.inbound_shipment_lines_for(actor, inbound_shipment_ids)
      shipments = InboundShipment.where(id: inbound_shipment_ids, purchase_order_id: Scope.call(actor, :own).select(:id))
      lines = InboundShipmentLine.where(inbound_shipment_id: shipments.select(:id)).order(:id).to_a
      accepted = ReceiptInspectionLine.where(inbound_shipment_line_id: lines.map(&:id)).pluck(:inbound_shipment_line_id, :accepted_quantity).to_h
      inbound_shipment_ids.index_with { [] }.merge(lines.map do |line|
        to_record_value(InboundShipmentLineValue, line, accepted_quantity: accepted[line.id])
      end.group_by(&:inbound_shipment_id))
    end

    # 入荷 ID ごとの検収。検収の前の入荷と見えない入荷は空
    def self.inspections_for(actor, inbound_shipment_ids)
      shipments = InboundShipment.where(id: inbound_shipment_ids, purchase_order_id: Scope.call(actor, :own).select(:id))
      ReceiptInspection.where(inbound_shipment_id: shipments.select(:id))
        .to_h { [ _1.inbound_shipment_id, to_record_value(ReceiptInspectionValue, _1) ] }
    end

    # 検収の対象の入荷。見えない ID は存在しない ID と同じく nil になる
    def self.find_inbound_shipment(actor, id)
      InboundShipment.where(id:, purchase_order_id: Scope.call(actor, :own).select(:id)).first
        &.then { to_record_value(InboundShipmentValue, _1) }
    end

    # statuses の空の配列は、Arel の In が 1=0 にするので 0 件になる（activerecord 8.1 の Arel::Visitors::ToSql#visit_Arel_Nodes_In）
    def self.filtered(relation, supplier_tenant_id: nil, order_date_from: nil, order_date_to: nil, statuses: nil)
      relation = relation.where(supplier_tenant_id:) if supplier_tenant_id
      relation = relation.where(order_date: order_date_from..) if order_date_from
      relation = relation.where(order_date: ..order_date_to) if order_date_to
      relation = relation.where(PurchaseOrderStatus.expression.in(statuses.map(&:to_s))) unless statuses.nil?
      relation
    end

    # 並べてよい列（docs/architecture/graphql-schema.md「ページングと N+1」）。伝票番号は桁をそろえた文字列なので、文字列の順が番号の順になる。
    # 受注側の名前は取引関係の公開 API の副問い合わせから引き、状況は業務の進み順の位置で並べる
    def self.order_columns(actor)
      orders = PurchaseOrder.arel_table
      { order_no: [ orders[:order_no], :string ],
        order_date: [ orders[:order_date], :date ],
        desired_delivery_on: [ orders[:desired_delivery_on], :date ],
        supplier_name: [ Partnerships::Directory.tenant_names_sql(actor).lookup(:name, :tenant_id, orders[:supplier_tenant_id]), :string ],
        total_amount: [ PurchaseOrderAmount.expression, :decimal ],
        status: [ Page::Sort.rank(PurchaseOrderStatus.expression, PurchaseOrderStatus::SORT_ORDER), :integer ] }
    end

    # 行と一緒に読む状況と合計金額の式
    def self.columns = [ PurchaseOrderStatus.expression.as("status"), PurchaseOrderAmount.expression.as("total_amount") ]

    def self.with_status(relation) = relation.select(PurchaseOrder.arel_table[Arel.star], *columns)

    # orders は状況と合計金額の式を status・total_amount の別名で読んだ発注。合計は numeric で読むので、整数に戻す
    def self.to_values(orders)
      orders = orders.to_a
      pending = CancellationRequest.pending.where(purchase_order_id: orders.map(&:id)).pluck(:purchase_order_id).to_set
      orders.map do |order|
        PurchaseOrderValue.new(id: order.id, owner_tenant_id: order.owner_tenant_id, order_no: order.order_no,
          supplier_tenant_id: order.supplier_tenant_id, order_date: order.order_date,
          desired_delivery_on: order.desired_delivery_on, status: order["status"].to_sym, cancellation_pending: pending.include?(order.id),
          total_amount: order["total_amount"]&.to_i)
      end
    end

    def self.to_cancellation_request_value(request)
      to_record_value(CancellationRequestValue, request).with(outcome: request.outcome&.to_sym)
    end

    def self.to_line_value(line) = to_record_value(PurchaseOrderLineValue, line)

    def self.to_record_value(klass, record, **extra)
      klass.new(**record.slice(*(klass.members - extra.keys).map(&:to_s)).symbolize_keys, **extra)
    end
    private_class_method :order_columns, :columns, :filtered, :with_status, :to_values, :to_cancellation_request_value, :to_line_value, :to_record_value
  end
end
