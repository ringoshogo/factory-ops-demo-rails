module Types
  class ShipmentLineType < BaseObject
    graphql_name "ShipmentLine"
    perspective :supplier
    authorize_with Fulfillment::ShipmentRequestPolicy

    field :id, ID, null: false
    field :shipment_request_line, ShipmentRequestLineType, null: false
    field :quantity, Int, null: false

    def shipment_request_line
      dataloader.with(Sources::PublicApiSource, Fulfillment::ShipmentRequests, :request_lines, context[:current_user])
        .load(object.shipment_request_line_id)
    end
  end
end
