module Fulfillment
  # 受注側が自社の出荷依頼と、その出荷指示・出荷実績を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）。
  # *_for は親の ID の配列を取り、ID ごとの値のハッシュを返す
  module ShipmentRequests
    def self.list(actor, first:, after:)
      Page.of(Scope.call(actor, ShipmentRequest.all), first:, after:) { |requests| to_values(actor, requests) }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      to_values(actor, Scope.call(actor, ShipmentRequest.where(id:))).first
    end

    # 受注 ID ごとの出荷依頼。出荷可能になる前の受注は含まない
    def self.for_sales_orders(actor, sales_order_ids)
      to_values(actor, Scope.call(actor, ShipmentRequest.where(sales_order_id: sales_order_ids))).index_by(&:sales_order_id)
    end

    def self.lines_for(actor, request_ids)
      lines = Scope.call(actor, ShipmentRequestLine.where(shipment_request_id: request_ids)).order(:id).map { to_value(ShipmentRequestLineValue, _1) }
      request_ids.index_with { [] }.merge(lines.group_by(&:shipment_request_id))
    end

    # 明細 ID ごとの出荷依頼の明細
    def self.request_lines(actor, line_ids)
      Scope.call(actor, ShipmentRequestLine.where(id: line_ids)).to_h { [ _1.id, to_value(ShipmentRequestLineValue, _1) ] }
    end

    # 出荷依頼 ID ごとの有効な出荷指示。無ければ含まない
    def self.instructions_for(actor, request_ids)
      Scope.call(actor, ShippingInstruction.active.where(shipment_request_id: request_ids))
        .to_h { [ _1.shipment_request_id, to_value(ShippingInstructionValue, _1) ] }
    end

    def self.shipments_for(actor, request_ids)
      Scope.call(actor, Shipment.where(shipment_request_id: request_ids)).to_h { [ _1.shipment_request_id, to_value(ShipmentValue, _1) ] }
    end

    def self.shipment_lines_for(actor, shipment_ids)
      lines = Scope.call(actor, ShipmentLine.where(shipment_id: shipment_ids)).order(:id).map { to_value(ShipmentLineValue, _1) }
      shipment_ids.index_with { [] }.merge(lines.group_by(&:shipment_id))
    end

    def self.to_values(actor, requests)
      requests = requests.to_a
      ids = requests.map(&:id)
      instructed = Scope.call(actor, ShippingInstruction.active.where(shipment_request_id: ids)).pluck(:shipment_request_id).to_set
      shipped = Scope.call(actor, Shipment.where(shipment_request_id: ids)).pluck(:shipment_request_id).to_set
      requests.map do |request|
        ShipmentRequestValue.new(id: request.id, owner_tenant_id: request.owner_tenant_id, sales_order_id: request.sales_order_id,
          buyer_tenant_id: request.buyer_tenant_id, due_date: request.due_date,
          status: ShipmentRequestStatus.derive(request, instructed: instructed.include?(request.id), shipped: shipped.include?(request.id)))
      end
    end

    def self.to_value(klass, record) = klass.new(**record.slice(*klass.members.map(&:to_s)).symbolize_keys)
    private_class_method :to_values, :to_value
  end
end
