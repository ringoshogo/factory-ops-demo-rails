module Types
  # 在庫の一覧の並べ替え。列の値が同じ行は ID で並べ、ページの境目で行が抜けも重なりもしない
  class StockOrderType < BaseInputObject
    graphql_name "StockOrder"

    argument :field, StockOrderFieldType
    argument :direction, OrderDirectionType
  end
end
