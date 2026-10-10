module Mutations
  # 入庫・出庫で現在庫を増減し、在庫移動履歴を 1 行足す。出庫は有効在庫までに限る。見えない品目は NOT_FOUND
  class AdjustStock < BaseMutation
    perspective :supplier
    authorize_with Inventory::StockPolicy, :adjust?
    audit_exempt reason: "効果が自社の中で閉じる"

    argument :item_id, ID
    argument :type, Types::StockAdjustmentType
    argument :quantity, Int
    argument :reason, String, required: false
    result_field :stock, Types::StockType

    # 在庫は受注に依存しないので、品目が自社のものかはここで受注の公開 API に問い合わせる
    def find_target(item_id:, **)
      Sales::Catalog.item(current_user, item_id)
    end

    def perform(target, type:, quantity:, reason: nil, **)
      Inventory::Adjustment.adjust(current_user, item_id: target.id, type:, quantity:, reason:)
    end
  end
end
