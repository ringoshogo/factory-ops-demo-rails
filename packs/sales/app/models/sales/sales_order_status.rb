module Sales
  # 受注の状況を、受注の時刻列と明細、在庫の引当から優先順で導出する
  # （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
  # allocated は受注明細 ID ごとの引当数量で、呼ぶ側が在庫の公開 API から得て渡す
  module SalesOrderStatus
    def self.derive(order, lines, allocated: {})
      if order.cancelled_at then :cancelled
      elsif order.inspected_at then :inspected
      elsif order.shipped_at then :shipped
      elsif lines.any? { !_1.matched? } then :awaiting_part_match
      elsif lines.all? { allocated.fetch(_1.id, 0) >= _1.quantity } then :allocated
      elsif lines.any? { allocated.fetch(_1.id, 0).positive? } then :partially_allocated
      else :received
      end
    end
  end
end
