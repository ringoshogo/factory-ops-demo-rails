module Types
  # 出荷依頼の一覧の並べ替え。列の値が同じ行は ID で並べ、ページの境目で行が抜けも重なりもしない
  class ShipmentRequestOrderType < BaseInputObject
    graphql_name "ShipmentRequestOrder"

    argument :field, ShipmentRequestOrderFieldType
    argument :direction, OrderDirectionType
  end
end
