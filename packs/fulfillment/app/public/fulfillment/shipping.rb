module Fulfillment
  # 出荷実績の計上（docs/architecture/graphql-schema.md「mutation の一覧」postShipment）。在庫の Inventory::Allocation で
  # 引当を消費し、現在庫と引当を減らす。ロックは出荷依頼 → 出荷指示 → 在庫 → 引当の順に取り、在庫と引当は在庫が取る。
  # 受注の取消と同時に進んでも、引当の行ロックでどちらか一方だけが成立する
  # （docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
  module Shipping
    # 有効な出荷指示のある出荷依頼を全量で計上し、「出荷計上」を出す。取消済・出荷済の出荷依頼、有効な指示の無い出荷依頼、
    # active でない引当を含む出荷依頼は、何も変えず CONFLICT を返す
    def self.post(actor, shipment_request_id:, shipped_on:)
      request = Scope.call(actor, ShipmentRequest.all).lock.find_by(id: shipment_request_id)
      return OperationResult.failure(:not_found, path: [ :shipment_request_id ]) unless request
      return conflict("Shipment request is cancelled or shipped") if request.cancelled_at || request.shipment

      instruction = request.instructions.active.lock.first
      return conflict("Shipment request has no active instruction") unless instruction

      result = nil
      ShipmentRequest.transaction(requires_new: true) do
        unless Inventory::Allocation.consume(actor, request.lines.map(&:sales_order_line_id)).success?
          result = conflict("Allocations are not active")
          raise ActiveRecord::Rollback
        end

        shipment = request.create_shipment!(owner_tenant_id: request.owner_tenant_id, shipping_instruction: instruction,
          buyer_tenant_id: request.buyer_tenant_id, source_purchase_order_id: request.source_purchase_order_id, shipped_on:,
          lines: request.lines.map do |line|
            ShipmentLine.new(owner_tenant_id: request.owner_tenant_id, shipment_request_line: line,
              source_purchase_order_line_id: line.source_purchase_order_line_id, quantity: line.quantity)
          end)
        publish_posted(request, shipment)
        result = OperationResult.success(ShipmentRequests.find(actor, request.id))
      end
      result
    end

    def self.publish_posted(request, shipment)
      Contracts.publish(Contracts::ShipmentPosted.new(
        shipment_id: shipment.id,
        sales_order_id: request.sales_order_id,
        purchase_order_id: shipment.source_purchase_order_id,
        supplier_tenant_id: shipment.owner_tenant_id,
        buyer_tenant_id: shipment.buyer_tenant_id,
        shipped_on: shipment.shipped_on.iso8601,
        lines: shipment.lines.map do |line|
          { "sales_order_line_id" => line.shipment_request_line.sales_order_line_id,
            "purchase_order_line_id" => line.source_purchase_order_line_id, "quantity" => line.quantity }
        end
      ))
    end

    def self.conflict(message) = OperationResult.failure(:conflict, message:)
    private_class_method :publish_posted, :conflict
  end
end
