module Purchasing
  # 発注側が自社の発注を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）
  module PurchaseOrders
    def self.list(actor, first:, after:)
      Page.of(Scope.call(actor, :own), first:, after:) { |orders| to_values(orders) }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      to_values(Scope.call(actor, :own).where(id:)).first
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

    # 入荷 ID ごとの入荷明細
    def self.inbound_shipment_lines_for(actor, inbound_shipment_ids)
      shipments = InboundShipment.where(id: inbound_shipment_ids, purchase_order_id: Scope.call(actor, :own).select(:id))
      lines = InboundShipmentLine.where(inbound_shipment_id: shipments.select(:id)).order(:id)
      inbound_shipment_ids.index_with { [] }
        .merge(lines.map { to_record_value(InboundShipmentLineValue, _1) }.group_by(&:inbound_shipment_id))
    end

    def self.to_values(orders)
      orders = orders.to_a
      inbound = InboundShipment.where(purchase_order_id: orders.map(&:id)).distinct.pluck(:purchase_order_id).to_set
      pending = CancellationRequest.pending.where(purchase_order_id: orders.map(&:id)).pluck(:purchase_order_id).to_set
      orders.map do |order|
        PurchaseOrderValue.new(id: order.id, owner_tenant_id: order.owner_tenant_id, order_no: order.order_no,
          supplier_tenant_id: order.supplier_tenant_id, order_date: order.order_date,
          desired_delivery_on: order.desired_delivery_on, status: PurchaseOrderStatus.derive(order, inbound: inbound.include?(order.id)),
          cancellation_pending: pending.include?(order.id))
      end
    end

    def self.to_cancellation_request_value(request)
      to_record_value(CancellationRequestValue, request).with(outcome: request.outcome&.to_sym)
    end

    def self.to_line_value(line) = to_record_value(PurchaseOrderLineValue, line)

    def self.to_record_value(klass, record) = klass.new(**record.slice(*klass.members.map(&:to_s)).symbolize_keys)
    private_class_method :to_values, :to_cancellation_request_value, :to_line_value, :to_record_value
  end
end
