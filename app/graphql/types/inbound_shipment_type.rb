module Types
  # 発注側が所有する入荷（「出荷計上」の写し）。受注側の出荷実績 ID は返さない
  class InboundShipmentType < BaseObject
    graphql_name "InboundShipment"
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy

    field :id, ID, null: false
    field :shipped_on, GraphQL::Types::ISO8601Date, null: false
    field :lines, [ InboundShipmentLineType ], null: false
    field :inspection, ReceiptInspectionType, description: "検収前は空"

    def lines = load_from(:inbound_shipment_lines_for)
    def inspection = load_from(:inspections_for)

    private

    def load_from(method)
      dataloader.with(Sources::PublicApiSource, Purchasing::PurchaseOrders, method, context[:current_user]).load(object.id)
    end
  end
end
