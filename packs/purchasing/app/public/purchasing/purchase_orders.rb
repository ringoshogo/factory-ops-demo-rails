module Purchasing
  # 発注側が自社の発注を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）
  module PurchaseOrders
    def self.list(actor, first:, after:)
      Page.of(Scope.call(actor, :own), first:, after:) { |orders| orders.map { to_value(_1) } }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      order = Scope.call(actor, :own).find_by(id:)
      order && to_value(order)
    end

    # 発注 ID ごとの明細。見えない発注の ID は空の配列になる
    def self.lines_for(actor, order_ids)
      lines = PurchaseOrderLine.where(purchase_order_id: Scope.call(actor, :own).where(id: order_ids).select(:id)).order(:id)
      order_ids.index_with { [] }.merge(lines.map { to_line_value(_1) }.group_by(&:purchase_order_id))
    end

    def self.to_value(order)
      PurchaseOrderValue.new(id: order.id, owner_tenant_id: order.owner_tenant_id, order_no: order.order_no,
        supplier_tenant_id: order.supplier_tenant_id, order_date: order.order_date,
        desired_delivery_on: order.desired_delivery_on, status: PurchaseOrderStatus.derive(order))
    end

    def self.to_line_value(line)
      PurchaseOrderLineValue.new(**line.slice(*PurchaseOrderLineValue.members.map(&:to_s)).symbolize_keys)
    end
    private_class_method :to_value, :to_line_value
  end
end
