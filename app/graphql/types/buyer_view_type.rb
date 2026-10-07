module Types
  # 発注側の視点。購買が所有するデータと、相手テナントを読む 3 経路だけを持つ
  class BuyerViewType < BaseObject
    graphql_name "BuyerView"
    perspective :buyer
    authorization_exempt reason: "データを持たない入口。フィールドはすべてリゾルバで、各自が宣言する"

    # フィールドは M8 以降の業務機能が足す
    has_no_fields true
  end
end
