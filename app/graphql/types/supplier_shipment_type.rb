module Types
  # 経路 3。受注側の出荷実績のうち、自社の発注に連結したもの。出荷実績 ID は返さず、連結先の発注で識別する
  class SupplierShipmentType < BaseObject
    graphql_name "SupplierShipment"
    perspective :buyer
    cross_tenant_read :shipments
    authorize_with Fulfillment::ShipmentRequestPolicy, :show_to_buyer?

    field :shipped_on, GraphQL::Types::ISO8601Date, null: false
    field :lines, [ SupplierShipmentLineType ], null: false
  end
end
