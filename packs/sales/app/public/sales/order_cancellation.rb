module Sales
  # 受注側の取消（docs/architecture/context-map.md「取消の流れ」、docs/architecture/graphql-schema.md「mutation の一覧」cancelSalesOrder）。
  # 審査を経ずに、受注の内部の取消の処理で引当の解除と cancelled_at を書き、購買へ「受注取消」を出す
  module OrderCancellation
    # 出荷済・取消済の受注と、引当が消費済みの受注は CONFLICT。未決の取消の審査がある受注も CONFLICT で、担当者は審査を承認する。
    # 審査中に取り消すと、後から届く審査の決着で、発注に「取消済み」と「受注側により取消」の 2 つの取消の時刻が並びうるからである。
    # 受注のロックを取ってから審査を読むので、同じ受注への「取消依頼」の受け手（審査を作る）と直列になる
    def self.cancel(actor, sales_order_id:)
      order = Scope.sales_orders(actor, :own).lock.find_by(id: sales_order_id)
      return OperationResult.failure(:not_found, path: [ :sales_order_id ]) unless order
      if order.cancellation_reviews.pending.exists?
        return OperationResult.failure(:conflict, message: "Sales order has a pending cancellation review")
      end

      result = nil
      SalesOrder.transaction(requires_new: true) do
        result = OrderCancelling.cancel(actor, order)
        raise ActiveRecord::Rollback unless result.success?

        Contracts.publish(Contracts::SalesOrderCancelled.new(purchase_order_id: order.source_purchase_order_id,
          buyer_tenant_id: order.customer_tenant_id, supplier_tenant_id: order.owner_tenant_id))
      end
      result.success? ? OperationResult.success(SalesOrders.find(actor, order.id)) : result
    end
  end
end
