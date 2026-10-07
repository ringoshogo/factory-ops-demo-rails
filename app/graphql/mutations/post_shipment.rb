module Mutations
  # 有効な出荷指示のある出荷依頼を全量で計上し、引当を消費して在庫を減らす。「出荷計上」を出す。
  # 有効な指示が無い出荷依頼と、active でない引当を含む出荷依頼は CONFLICT
  class PostShipment < BaseMutation
    perspective :supplier
    authorize_with Fulfillment::ShipmentRequestPolicy, :ship?

    argument :shipment_request_id, ID
    argument :shipped_on, GraphQL::Types::ISO8601Date
    result_field :shipment_request, Types::ShipmentRequestType

    def find_target(shipment_request_id:, **)
      Fulfillment::ShipmentRequests.find(current_user, shipment_request_id)
    end

    def perform(target, shipped_on:, **)
      Fulfillment::Shipping.post(current_user, shipment_request_id: target.id, shipped_on:)
    end
  end
end
