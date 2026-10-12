module Types
  # 在庫移動履歴の一覧の絞り込み
  class StockMovementFilterType < BaseInputObject
    graphql_name "StockMovementFilter"

    argument :types, [ StockMovementKindType ], required: false, description: "移動の種類。空の配列は 0 件を返し、省くか null なら絞らない"
  end
end
