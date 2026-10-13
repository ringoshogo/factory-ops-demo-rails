module Types
  # 発注の一覧の絞り込み。発注日は orderDateFrom 以上・orderDateTo 以下で、始まりが終わりより後なら空になる
  class PurchaseOrderFilterType < BaseInputObject
    graphql_name "PurchaseOrderFilter"

    argument :supplier_tenant_id, ID, required: false
    argument :order_date_from, GraphQL::Types::ISO8601Date, required: false
    argument :order_date_to, GraphQL::Types::ISO8601Date, required: false
  end
end
