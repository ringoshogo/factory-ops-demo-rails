module Types
  # 受注の一覧の並べ替え。列の値が同じ行は ID で並べ、ページの境目で行が抜けも重なりもしない
  class SalesOrderOrderType < BaseInputObject
    graphql_name "SalesOrderOrder"

    argument :field, SalesOrderOrderFieldType
    argument :direction, OrderDirectionType
  end
end
