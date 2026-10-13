module Types
  # 発注の一覧の並べ替え。列の値が同じ行は ID で並べ、ページの境目で行が抜けも重なりもしない
  class PurchaseOrderOrderType < BaseInputObject
    graphql_name "PurchaseOrderOrder"

    argument :field, PurchaseOrderOrderFieldType
    argument :direction, OrderDirectionType
  end
end
