module Mutations
  # 出荷依頼の有効な出荷指示を取り消す。有効な指示が無いか、出荷済みなら CONFLICT
  class CancelShippingInstruction < BaseMutation
    perspective :supplier
    authorize_with Fulfillment::ShipmentRequestPolicy, :instruct?
    audit_exempt reason: "効果が自社の中で閉じる"

    argument :shipment_request_id, ID
    result_field :shipment_request, Types::ShipmentRequestType

    def find_target(shipment_request_id:, **)
      Fulfillment::ShipmentRequests.find(current_user, shipment_request_id)
    end

    def perform(target, **)
      Fulfillment::Instructions.cancel(current_user, shipment_request_id: target.id)
    end
  end
end
