module Sales
  # 受注の引当（docs/architecture/graphql-schema.md「mutation の一覧」allocateSalesOrder）。在庫の Inventory::Allocation を
  # 同じトランザクションで呼ぶ。ロックは受注 → 受注明細（id 順）→ 在庫 → 引当の順に取り、在庫と引当は在庫が取る
  # （docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
  module OrderAllocation
    # 各明細の未引当の量を、有効在庫の範囲で引き当てる。この引当で全明細が全量引当になったら「出荷可能」を出す。
    # 品番照合待ち・取消済・出荷済の受注は引き当てず CONFLICT を返す
    def self.allocate(actor, sales_order_id:)
      order = Scope.sales_orders(actor, :own).lock.find_by(id: sales_order_id)
      return OperationResult.failure(:not_found, path: [ :sales_order_id ]) unless order
      return OperationResult.failure(:conflict, message: "Sales order is cancelled or shipped") if order.cancelled_at || order.shipped_at

      lines = order.lines.lock.to_a
      return OperationResult.failure(:conflict, message: "Sales order is awaiting part match") unless lines.all?(&:matched?)

      before = Inventory::Allocation.quantities_for(actor, lines.map(&:id))
      after = Inventory::Allocation.allocate(actor,
        lines.map { { sales_order_line_id: _1.id, item_id: _1.item_id, quantity: _1.quantity } })
      publish_ready(order, lines) if !fully_allocated?(lines, before) && fully_allocated?(lines, after)
      OperationResult.success(SalesOrders.find(actor, order.id))
    end

    def self.fully_allocated?(lines, quantities) = lines.all? { quantities.fetch(_1.id) >= _1.quantity }

    def self.publish_ready(order, lines)
      Contracts.publish(Contracts::SalesOrderReadyForShipment.new(
        sales_order_id: order.id,
        sales_order_no: order.order_no,
        supplier_tenant_id: order.owner_tenant_id,
        buyer_tenant_id: order.customer_tenant_id,
        purchase_order_id: order.source_purchase_order_id,
        due_date: order.due_date&.iso8601,
        lines: lines.map do |line|
          { "sales_order_line_id" => line.id, "purchase_order_line_id" => line.source_purchase_order_line_id,
            "item_id" => line.item_id, "quantity" => line.quantity }
        end
      ))
    end
    private_class_method :fully_allocated?, :publish_ready
  end
end
