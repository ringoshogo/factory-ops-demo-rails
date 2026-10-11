module Types
  # 受注の状況ごとの件数。ダッシュボードのフィールドとしてだけ現れる
  class SalesOrderStatusCountType < BaseObject
    graphql_name "SalesOrderStatusCount"
    perspective :supplier
    authorization_exempt reason: "自社の受注の件数だけを持ち、認可済みのリゾルバが返す SupplierDashboard のフィールドとしてだけ現れる"

    field :status, SalesOrderStatusType, null: false
    field :count, Int, null: false
  end
end
