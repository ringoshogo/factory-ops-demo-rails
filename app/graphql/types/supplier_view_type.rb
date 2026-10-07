module Types
  # 受注側の視点。受注・在庫・出荷・請求・取引関係が所有するデータを持つ
  class SupplierViewType < BaseObject
    graphql_name "SupplierView"
    perspective :supplier
    authorization_exempt reason: "データを持たない入口。フィールドはすべてリゾルバで、各自が宣言する"

    # フィールドは M8 以降の業務機能が足す
    has_no_fields true
  end
end
