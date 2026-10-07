module Purchasing
  # 発注の登録（docs/architecture/context-map.md「発注の連結と品番の照合」1、「取引関係の失効」）
  module Ordering
    # 1 件の発注の入力の上限（docs/architecture/graphql-schema.md「mutation の一覧」）
    MAX_LINES = 100
    MAX_PART_NUMBER_LENGTH = 64

    # lines は { part_number:, quantity: } の配列。相手への place_orders を取引関係の公開 API に問い合わせ、
    # 無ければ NOT_PERMITTED を返す。存在しない・関係の無い・失効した・付与の無い相手を区別しない。
    # 問い合わせは組のロックを取り、失効・撤回がコミットまで割り込まないようにする。
    # 発注と「発注登録」のジョブは同じセーブポイントの中で書き、失敗を返すときは両方を戻す
    def self.place(actor, supplier_tenant_id:, lines:, desired_delivery_on: nil)
      unless Partnerships::Access.permitted?(actor, supplier_tenant_id:, permission: :place_orders, lock: true)
        return OperationResult.failure(:not_permitted, path: [ :supplier_tenant_id ])
      end

      invalid = invalid_line(lines)
      return invalid if invalid

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

    # 入力の誤りがある最初の項目を INVALID_INPUT で返す。明細が無いか多すぎれば明細全体を指す
    def self.invalid_line(lines)
      return invalid_input([ :lines ], "Lines can't be empty") if lines.empty?
      return invalid_input([ :lines ], "Lines must be at most #{MAX_LINES}") if lines.size > MAX_LINES

      seen = Set.new
      lines.each_with_index do |line, index|
        part_number = line[:part_number]
        if part_number.blank? || !seen.add?(part_number)
          return invalid_input([ :lines, index, :part_number ], "Part number must be present and unique")
        end
        if part_number.length > MAX_PART_NUMBER_LENGTH
          return invalid_input([ :lines, index, :part_number ], "Part number must be at most #{MAX_PART_NUMBER_LENGTH} characters")
        end
        unless line[:quantity].is_a?(Integer) && line[:quantity].positive?
          return invalid_input([ :lines, index, :quantity ], "Quantity must be positive")
        end
      end
      nil
    end

    def self.invalid_input(path, message) = OperationResult.failure(:invalid_input, path:, message:)

    def self.publish(order)
      Contracts.publish(Contracts::PurchaseOrderPlaced.new(
        purchase_order_id: order.id,
        buyer_tenant_id: order.owner_tenant_id,
        supplier_tenant_id: order.supplier_tenant_id,
        desired_delivery_on: order.desired_delivery_on&.iso8601,
        lines: order.lines.map { { "purchase_order_line_id" => _1.id, "part_number" => _1.part_number, "quantity" => _1.quantity } }
      ))
    end
    private_class_method :invalid_line, :invalid_input, :publish
  end
end
