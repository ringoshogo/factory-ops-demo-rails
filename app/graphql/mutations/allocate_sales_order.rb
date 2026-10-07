module Mutations
  # 受注の各明細を有効在庫の範囲で引き当てる。全量引当になったら「出荷可能」を出す。
  # 品番照合待ち・取消済・出荷済の受注は CONFLICT
  class AllocateSalesOrder < BaseMutation
    perspective :supplier
    authorize_with Sales::SalesOrderPolicy, :allocate?

    argument :sales_order_id, ID
    result_field :sales_order, Types::SalesOrderType

    # 自社の受注だけを引く。見えない ID は NOT_FOUND になる
    def find_target(sales_order_id:, **)
      Sales::SalesOrders.find(current_user, sales_order_id)
    end

    def perform(target, **)
      Sales::OrderAllocation.allocate(current_user, sales_order_id: target.id)
    end
  end
end
