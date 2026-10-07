module Sales
  # 受注側が自社の受注を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）。
  # 状況と引当数量は、在庫の Inventory::Allocation から受注明細 ID ごとの引当数量をまとめて得て導出する
  module SalesOrders
    def self.list(actor, first:, after:)
      Page.of(Scope.sales_orders(actor, :own), first:, after:) { |orders| to_values(actor, orders) }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      to_values(actor, Scope.sales_orders(actor, :own).where(id:)).first
    end

    # 受注 ID ごとの受注。見えない ID は含まない
    def self.by_ids(actor, ids)
      to_values(actor, Scope.sales_orders(actor, :own).where(id: ids)).index_by(&:id)
    end

    # 受注 ID ごとの明細。見えない受注の ID は空の配列になる
    def self.lines_for(actor, order_ids)
      lines = SalesOrderLine.where(sales_order_id: Scope.sales_orders(actor, :own).where(id: order_ids).select(:id)).order(:id).to_a
      allocated = Inventory::Allocation.quantities_for(actor, lines.map(&:id))
      order_ids.index_with { [] }.merge(lines.map { to_line_value(_1, allocated) }.group_by(&:sales_order_id))
    end

    # 受注明細 ID ごとの明細。見えない ID は含まない
    def self.lines_by_ids(actor, line_ids)
      lines = SalesOrderLine.where(id: line_ids, sales_order_id: Scope.sales_orders(actor, :own).select(:id)).to_a
      allocated = Inventory::Allocation.quantities_for(actor, lines.map(&:id))
      lines.to_h { [ _1.id, to_line_value(_1, allocated) ] }
    end

    def self.to_values(actor, orders)
      orders = orders.to_a
      lines = SalesOrderLine.where(sales_order_id: orders.map(&:id)).to_a
      allocated = Inventory::Allocation.quantities_for(actor, lines.map(&:id))
      lines = lines.group_by(&:sales_order_id)
      orders.map do |order|
        SalesOrderValue.new(id: order.id, owner_tenant_id: order.owner_tenant_id, order_no: order.order_no,
          customer_tenant_id: order.customer_tenant_id, order_date: order.order_date, due_date: order.due_date,
          status: SalesOrderStatus.derive(order, lines.fetch(order.id, []), allocated:))
      end
    end

    def self.to_line_value(line, allocated)
      SalesOrderLineValue.new(**line.slice(*(SalesOrderLineValue.members - [ :allocated_quantity ]).map(&:to_s)).symbolize_keys,
        allocated_quantity: allocated.fetch(line.id))
    end
    private_class_method :to_values, :to_line_value
  end
end
