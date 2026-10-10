module Types
  class ReceiptInspectionLineInputType < BaseInputObject
    graphql_name "ReceiptInspectionLineInput"

    argument :inbound_shipment_line_id, ID
    argument :accepted_quantity, Int, description: "0 以上・出荷数量以下。0 は全量の不合格"
  end
end
