module Types
  # 型の名前の StockMovementType は在庫移動履歴の object の型が使うので、enum のクラスはこの名前にする
  class StockMovementKindType < BaseEnum
    graphql_name "StockMovementType"

    value "INBOUND", "入庫", value: "inbound"
    value "OUTBOUND", "出庫", value: "outbound"
    value "ALLOCATE", "引当", value: "allocate"
    value "DEALLOCATE", "引当の解除", value: "deallocate"
    value "SHIP", "出荷", value: "ship"
  end
end
