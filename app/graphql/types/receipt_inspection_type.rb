module Types
  # 発注側が所有する入荷検収。検収数量は入荷の明細（InboundShipmentLine.acceptedQuantity）に示す
  class ReceiptInspectionType < BaseObject
    graphql_name "ReceiptInspection"
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy

    field :inspected_on, GraphQL::Types::ISO8601Date, null: false
  end
end
