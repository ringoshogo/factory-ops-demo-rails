module Types
  # adjustStock で選べる移動の種類。引当と出荷による移動は、引当と出荷計上の操作だけが起こす
  class StockAdjustmentType < BaseEnum
    graphql_name "StockAdjustmentType"

    value "INBOUND", "入庫", value: "inbound"
    value "OUTBOUND", "出庫", value: "outbound"
  end
end
