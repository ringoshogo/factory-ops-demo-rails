module Types
  # 受注側が所有する出荷実績。発注側が読む SupplierShipment（M14）とは別の型にする
  class ShipmentType < BaseObject
    graphql_name "Shipment"
    perspective :supplier
    authorize_with Fulfillment::ShipmentRequestPolicy

    field :id, ID, null: false
    field :shipped_on, GraphQL::Types::ISO8601Date, null: false
    field :lines, [ ShipmentLineType ], null: false

    def lines
      dataloader.with(Sources::PublicApiSource, Fulfillment::ShipmentRequests, :shipment_lines_for, context[:current_user]).load(object.id)
    end
  end
end
