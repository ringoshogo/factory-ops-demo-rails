module Sales
  # 受注の内部の取消の処理。審査の承認と受注側の取消が通る。引当の解除と受注の cancelled_at を、呼ぶ側のトランザクションの中で
  # 一緒に書く。出荷依頼の取消済は、出荷が受注の cancelled_at から導出するので、出荷へは何も出さない。
  # ロックは受注 → 受注明細（id 順）→ 在庫 → 引当の順に取り、受注は呼ぶ側がロックしておく。出荷の計上も受注の行を最初にロックするので、
  # 同時に進んでも受注の行ロックで直列になる（docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
  module OrderCancelling
    # 出荷済・取消済の受注と、消費済み（出荷済み）の引当を含む受注は、何も書かずに CONFLICT を返す
    def self.cancel(actor, order)
      return conflict("Sales order is cancelled or shipped") if order.cancelled_at || order.shipped_at

      line_ids = order.lines.lock.ids
      return conflict("Allocations are consumed") unless Inventory::Allocation.release(actor, line_ids).success?

      order.update!(cancelled_at: Time.current)
      OperationResult.success
    end

    def self.conflict(message) = OperationResult.failure(:conflict, message:)
    private_class_method :conflict
  end
end
