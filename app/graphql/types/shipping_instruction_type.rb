module Types
  # 有効な出荷指示。取り消した指示は ShipmentRequest.instruction に現れないので、状態のフィールドを持たない
  class ShippingInstructionType < BaseObject
    graphql_name "ShippingInstruction"
    perspective :supplier
    authorize_with Fulfillment::ShipmentRequestPolicy

    field :id, ID, null: false
    field :planned_date, GraphQL::Types::ISO8601Date, null: false
  end
end
