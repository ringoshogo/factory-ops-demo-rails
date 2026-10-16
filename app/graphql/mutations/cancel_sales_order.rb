module Mutations
  # 自社の受注を、審査を経ずに取り消す。引当を解除し、「受注取消」を出す。出荷は受注の取消を読んで出荷依頼を取消済にする。
  # 出荷済・取消済の受注、未決の取消の審査がある受注、引当が消費済みの受注は CONFLICT
  class CancelSalesOrder < BaseMutation
    perspective :supplier
    authorize_with Sales::SalesOrderPolicy, :cancel?
    audit "sales_order.cancel", target: ->(target:, **) { target }, counterparty: ->(target:, **) { target.customer_tenant_id }

    argument :sales_order_id, ID
    result_field :sales_order, Types::SalesOrderType

    # 自社の受注だけを引く。見えない ID は NOT_FOUND になる
    def find_target(sales_order_id:, **)
      Sales::SalesOrders.find(current_user, sales_order_id)
    end

    def perform(target, **)
      Sales::OrderCancellation.cancel(current_user, sales_order_id: target.id)
    end
  end
end
