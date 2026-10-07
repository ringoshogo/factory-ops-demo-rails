module Types
  class QueryType < BaseObject
    perspective :root
    authorization_exempt reason: "ルートの型。フィールドはすべてリゾルバか mutation で、各自が宣言する"

    field :viewer, ViewerType, null: false
    field :buyer, BuyerViewType, null: false, description: "発注側の視点"
    field :supplier, SupplierViewType, null: false, description: "受注側の視点"

    def viewer
      Current.actor
    end

    # 入口はデータを持たない。各フィールドのリゾルバが操作者で公開 API を呼ぶ
    def buyer = {}
    def supplier = {}
  end
end
