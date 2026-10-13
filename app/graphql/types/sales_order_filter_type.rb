module Types
  # 受注の一覧の絞り込み。受注日は orderDateFrom 以上・orderDateTo 以下で、始まりが終わりより後なら空になる
  class SalesOrderFilterType < BaseInputObject
    graphql_name "SalesOrderFilter"

    argument :customer_tenant_id, ID, required: false
    argument :order_date_from, GraphQL::Types::ISO8601Date, required: false
    argument :order_date_to, GraphQL::Types::ISO8601Date, required: false
    argument :statuses, [ SalesOrderStatusType ], required: false,
      description: "状況。空の配列は 0 件を返し、省くか null なら絞らない。取消審査中は状況ではないので含めない"
  end
end
