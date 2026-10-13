module Types
  # 品目の一覧の並べ替え。列の値が同じ行は ID で並べ、ページの境目で行が抜けも重なりもしない
  class ItemOrderType < BaseInputObject
    graphql_name "ItemOrder"

    argument :field, ItemOrderFieldType
    argument :direction, OrderDirectionType
  end
end
