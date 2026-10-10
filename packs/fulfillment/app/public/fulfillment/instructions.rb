module Fulfillment
  # 出荷指示の作成と取消（docs/architecture/graphql-schema.md「mutation の一覧」）。出荷依頼の行をロックして、同じ出荷依頼への
  # 操作を直列にする。有効な指示が出荷依頼ごとに 1 件であることは、部分一意索引が最後に守る
  module Instructions
    # 取消済・出荷済の出荷依頼と、有効な指示がすでにある出荷依頼と、出荷停止中の受注の出荷依頼は CONFLICT
    def self.create(actor, shipment_request_id:, planned_date:)
      request = Scope.call(actor, ShipmentRequest.all).lock.find_by(id: shipment_request_id)
      return OperationResult.failure(:not_found, path: [ :shipment_request_id ]) unless request
      return conflict("Shipment request is cancelled or shipped") if request.cancelled_at || request.shipment
      return conflict("Sales order is on hold") if request.held?
      return conflict("Shipment request already has an active instruction") if request.instructions.active.exists?

      request.instructions.create!(owner_tenant_id: request.owner_tenant_id, planned_date:)
      OperationResult.success(ShipmentRequests.find(actor, request.id))
    end

    # 有効な指示を取り消す。有効な指示が無いか、出荷済みなら CONFLICT
    def self.cancel(actor, shipment_request_id:)
      request = Scope.call(actor, ShipmentRequest.all).lock.find_by(id: shipment_request_id)
      return OperationResult.failure(:not_found, path: [ :shipment_request_id ]) unless request
      return conflict("Shipment request is shipped") if request.shipment

      instruction = request.instructions.active.lock.first
      return conflict("Shipment request has no active instruction") unless instruction

      instruction.update!(status: "cancelled")
      OperationResult.success(ShipmentRequests.find(actor, request.id))
    end

    def self.conflict(message) = OperationResult.failure(:conflict, message:)
    private_class_method :conflict
  end
end
