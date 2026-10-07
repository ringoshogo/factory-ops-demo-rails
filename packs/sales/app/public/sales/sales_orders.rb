module Sales
  # 受注側が自社の受注を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）。
  # 引当の量は M12 で在庫の Inventory::Allocation から得る。それまでは 0 とする
  module SalesOrders
    def self.list(actor, first:, after:)
      Page.of(Scope.sales_orders(actor, :own), first:, after:) { |orders| to_values(orders) }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      to_values(Scope.sales_orders(actor, :own).where(id:)).first
    end

    # 受注 ID ごとの明細。見えない受注の ID は空の配列になる
    def self.lines_for(actor, order_ids)
      lines = SalesOrderLine.where(sales_order_id: Scope.sales_orders(actor, :own).where(id: order_ids).select(:id)).order(:id)
      order_ids.index_with { [] }.merge(lines.map { to_line_value(_1) }.group_by(&:sales_order_id))
    end

    def self.to_values(orders)
      orders = orders.to_a
      lines = SalesOrderLine.where(sales_order_id: orders.map(&:id)).group_by(&:sales_order_id)
      orders.map do |order|
        SalesOrderValue.new(id: order.id, owner_tenant_id: order.owner_tenant_id, order_no: order.order_no,
          customer_tenant_id: order.customer_tenant_id, order_date: order.order_date, due_date: order.due_date,
          status: SalesOrderStatus.derive(order, lines.fetch(order.id, [])))
      end
    end

    def self.to_line_value(line)
      SalesOrderLineValue.new(**line.slice(*(SalesOrderLineValue.members - [ :allocated_quantity ]).map(&:to_s)).symbolize_keys,
        allocated_quantity: 0)
    end
    private_class_method :to_values, :to_line_value
  end
end
