module Purchasing
  # 入荷検収（docs/architecture/context-map.md「検収と請求の流れ」1、「取引関係の失効」）
  module ReceiptInspections
    # 入力の上限（docs/architecture/graphql-schema.md「mutation の一覧」）。発注の明細の上限と同じなので、正しい入力は必ず収まる
    MAX_LINES = Ordering::MAX_LINES

    # lines は { inbound_shipment_line_id:, accepted_quantity: } の配列で、入荷の全明細を 1 回ずつ並べる。
    # 検収数量は 0 以上・出荷数量以下の整数で、0 は全量の不合格を表す。明細の省略・重複・別の入荷の明細と数量の誤りは
    # INVALID_INPUT、同じ入荷への 2 回目は CONFLICT。検収日は登録した日にする。
    # 入荷の行ロックで同じ入荷への検収を直列にし、inbound_shipment_id の一意索引が最後に守る。
    # 取引関係の状態は見ない。連結済みの発注は、失効の後も検収できる
    def self.record(actor, inbound_shipment_id:, lines:)
      inbound = InboundShipment.where(purchase_order_id: Scope.call(actor, :own).select(:id)).lock.find_by(id: inbound_shipment_id)
      return OperationResult.failure(:not_found, path: [ :inbound_shipment_id ]) unless inbound

      invalid = invalid_line(inbound, lines)
      return invalid if invalid
      return OperationResult.failure(:conflict, message: "Inbound shipment is already inspected") if inbound.inspection

      ReceiptInspection.transaction(requires_new: true) do
        inspection = inbound.create_inspection!(owner_tenant_id: inbound.owner_tenant_id, inspected_on: Date.current,
          lines: lines.map do |line|
            ReceiptInspectionLine.new(owner_tenant_id: inbound.owner_tenant_id,
              inbound_shipment_line_id: line[:inbound_shipment_line_id], accepted_quantity: line[:accepted_quantity])
          end)
        publish(inbound, inspection)
      end
      OperationResult.success(PurchaseOrders.find(actor, inbound.purchase_order_id))
    end

    # 入力の誤りがある最初の明細を INVALID_INPUT で返す。件数の超過と明細の省略は明細全体を指す
    def self.invalid_line(inbound, lines)
      return invalid_input([ :lines ], "Lines must be at most #{MAX_LINES}") if lines.size > MAX_LINES

      shipped = inbound.lines.to_h { [ _1.id, _1.shipped_quantity ] }
      seen = Set.new
      lines.each_with_index do |line, index|
        line_id = line[:inbound_shipment_line_id]
        unless shipped.key?(line_id) && seen.add?(line_id)
          return invalid_input([ :lines, index, :inbound_shipment_line_id ], "Line must be a unique line of the inbound shipment")
        end

        quantity = line[:accepted_quantity]
        unless quantity.is_a?(Integer) && quantity.between?(0, shipped.fetch(line_id))
          return invalid_input([ :lines, index, :accepted_quantity ], "Accepted quantity must be between 0 and the shipped quantity")
        end
      end
      return invalid_input([ :lines ], "Lines must cover every line of the inbound shipment") if seen.size < shipped.size

      nil
    end

    def self.invalid_input(path, message) = OperationResult.failure(:invalid_input, path:, message:)

    def self.publish(inbound, inspection)
      order = inbound.purchase_order
      purchase_order_lines = inbound.lines.to_h { [ _1.id, _1.purchase_order_line_id ] }
      Contracts.publish(Contracts::ReceiptInspected.new(
        shipment_id: inbound.shipment_id,
        purchase_order_id: order.id,
        buyer_tenant_id: order.owner_tenant_id,
        supplier_tenant_id: order.supplier_tenant_id,
        inspected_on: inspection.inspected_on.iso8601,
        lines: inspection.lines.map do |line|
          { "purchase_order_line_id" => purchase_order_lines.fetch(line.inbound_shipment_line_id),
            "accepted_quantity" => line.accepted_quantity }
        end
      ))
    end
    private_class_method :invalid_line, :invalid_input, :publish
  end
end
