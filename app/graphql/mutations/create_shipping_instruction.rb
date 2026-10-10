module Mutations
  # 出荷依頼に出荷指示を作る。取消済・出荷済の出荷依頼と、有効な指示がすでにある出荷依頼は CONFLICT
  class CreateShippingInstruction < BaseMutation
    perspective :supplier
    authorize_with Fulfillment::ShipmentRequestPolicy, :instruct?
    audit_exempt reason: "効果が自社の中で閉じる"

    argument :shipment_request_id, ID
    argument :planned_date, GraphQL::Types::ISO8601Date
    result_field :shipment_request, Types::ShipmentRequestType

    # 自社の出荷依頼だけを引く。見えない ID は NOT_FOUND になる
    def find_target(shipment_request_id:, **)
      Fulfillment::ShipmentRequests.find(current_user, shipment_request_id)
    end

    def perform(target, planned_date:, **)
      Fulfillment::Instructions.create(current_user, shipment_request_id: target.id, planned_date:)
    end
  end
end
