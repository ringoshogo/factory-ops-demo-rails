module Mutations
  # 自社の発注に取消を依頼し、「取消依頼」を出す。回答待ちの依頼がある発注と、取消済みの発注は CONFLICT
  class RequestPurchaseOrderCancellation < BaseMutation
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy, :request_cancellation?
    audit "purchase_order.request_cancellation", target: ->(target:, **) { target },
      counterparty: ->(target:, **) { target.supplier_tenant_id }

    argument :purchase_order_id, ID
    argument :reason, String
    result_field :purchase_order, Types::PurchaseOrderType

    # 自社の発注だけを引く。見えない ID は NOT_FOUND になる
    def find_target(purchase_order_id:, **)
      Purchasing::PurchaseOrders.find(current_user, purchase_order_id)
    end

    def perform(target, reason:, **)
      Purchasing::Ordering.request_cancellation(current_user, purchase_order_id: target.id, reason:)
    end
  end
end
