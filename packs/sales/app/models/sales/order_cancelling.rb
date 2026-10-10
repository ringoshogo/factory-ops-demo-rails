module Sales
  # 受注の内部の取消の処理。審査の承認と受注側の取消が通る。引当の解除と受注の cancelled_at を、呼ぶ側のトランザクションの中で
  # 一緒に書き、「出荷取消」を出す。ロックは受注 → 受注明細（id 順）→ 在庫 → 引当の順に取り、受注は呼ぶ側がロックしておく。
  # 出荷の計上と同時に進んでも、引当の行ロックでどちらか一方だけが成立する（docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
  module OrderCancelling
    # 出荷済・取消済の受注と、消費済み（出荷済み）の引当を含む受注は、何も書かずに CONFLICT を返す。
    # cancellation_review_id は取消を承認した審査で、出荷は「出荷取消」でその審査の出荷停止も解除する
    def self.cancel(actor, order, cancellation_review_id: nil)
      return conflict("Sales order is cancelled or shipped") if order.cancelled_at || order.shipped_at

      lines = order.lines.lock.to_a
      line_ids = lines.map(&:id)
      # 「出荷可能」は全明細が全量引当になったときに出し、全量引当は解除か消費でしか崩れない。
      # そのため、解除の前に引当済なら、この受注について「出荷可能」を出している
      ready = SalesOrderStatus.derive(order, lines, allocated: Inventory::Allocation.quantities_for(actor, line_ids)) == :allocated
      return conflict("Allocations are consumed") unless Inventory::Allocation.release(actor, line_ids).success?

      order.update!(cancelled_at: Time.current)
      Contracts.publish(Contracts::ShipmentCancelled.new(sales_order_id: order.id, supplier_tenant_id: order.owner_tenant_id,
        cancellation_review_id:, ready_for_shipment: ready))
      OperationResult.success
    end

    def self.conflict(message) = OperationResult.failure(:conflict, message:)
    private_class_method :conflict
  end
end
