module Purchasing
  # 発注の登録（docs/architecture/context-map.md「発注の連結と品番の照合」1、「取引関係の失効」）
  module Ordering
    # lines は { part_number:, quantity: } の配列。相手への place_orders を取引関係の公開 API に問い合わせ、
    # 無ければ NOT_PERMITTED を返す。存在しない・関係の無い・失効した・付与の無い相手を区別しない。
    # 発注と「発注登録」のジョブは同じセーブポイントの中で書き、失敗を返すときは両方を戻す
    def self.place(actor, supplier_tenant_id:, lines:, desired_delivery_on: nil)
      unless Partnerships::Access.permitted?(actor, supplier_tenant_id:, permission: :place_orders)
        return OperationResult.failure(:not_permitted, path: [ :supplier_tenant_id ])
      end

      invalid = invalid_line(lines)
      return OperationResult.failure(:invalid_input, path: invalid) if invalid

      order = PurchaseOrder.transaction(requires_new: true) do
        PurchaseOrder.create!(
          owner_tenant_id: actor.tenant_id,
          order_no: DocumentNumber.next(PurchaseOrderSequence, prefix: "PO"),
          supplier_tenant_id:,
          order_date: Date.current,
          desired_delivery_on:,
          lines: lines.map { |line| PurchaseOrderLine.new(owner_tenant_id: actor.tenant_id, **line.slice(:part_number, :quantity)) }
        ).tap { publish(_1) }
      end
      OperationResult.success(PurchaseOrders.find(actor, order.id))
    end

    # 入力の誤りがある明細の項目を返す。明細が無ければ明細全体を指す
    def self.invalid_line(lines)
      return [ :lines ] if lines.empty?

      seen = Set.new
      lines.each_with_index do |line, index|
        return [ :lines, index, :part_number ] if line[:part_number].blank? || !seen.add?(line[:part_number])
        return [ :lines, index, :quantity ] unless line[:quantity].is_a?(Integer) && line[:quantity].positive?
      end
      nil
    end

    def self.publish(order)
      Contracts.publish(Contracts::PurchaseOrderPlaced.new(
        purchase_order_id: order.id,
        buyer_tenant_id: order.owner_tenant_id,
        supplier_tenant_id: order.supplier_tenant_id,
        desired_delivery_on: order.desired_delivery_on&.iso8601,
        lines: order.lines.map { { "purchase_order_line_id" => _1.id, "part_number" => _1.part_number, "quantity" => _1.quantity } }
      ))
    end
    private_class_method :invalid_line, :publish
  end
end
