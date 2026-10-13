module Types
  # 出荷依頼の一覧の絞り込み
  class ShipmentRequestFilterType < BaseInputObject
    graphql_name "ShipmentRequestFilter"

    argument :statuses, [ ShipmentRequestStatusType ], required: false, description: "状況。空の配列は 0 件を返し、省くか null なら絞らない"
  end
end
