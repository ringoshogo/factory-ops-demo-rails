module Sales
  # 受注側が自社の受注を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）。
  # 状況と引当数量は、在庫の Inventory::Allocation から受注明細 ID ごとの引当数量をまとめて得て導出する
  module SalesOrders
    # 並べてよい列（docs/architecture/graphql-schema.md「ページングと N+1」）。伝票番号は桁をそろえた文字列なので、文字列の順が番号の順になる
    ORDER_COLUMNS = {
      order_no: [ SalesOrder.arel_table[:order_no], :string ],
      order_date: [ SalesOrder.arel_table[:order_date], :date ],
      due_date: [ SalesOrder.arel_table[:due_date], :date ]
    }.freeze

    # order_by は { field:, direction: } で、省けば作った順の新しいものから並べる。
    # filter は得意先と、両端を含む受注日の範囲で絞る
    def self.list(actor, first:, after:, order_by: nil, filter: {})
      Page.of(filtered(Scope.sales_orders(actor, :own), **filter), first:, after:, sort: Page::Sort.of(order_by, ORDER_COLUMNS)) do |orders|
        to_values(actor, orders)
      end
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

    # 状況ごとの受注の件数。受注一覧と同じ導出で数え、取消済を含む 7 つの状況をすべて持つ（0 件の状況も返す）
    def self.count_by_status(actor)
      counts = to_values(actor, Scope.sales_orders(actor, :own)).map(&:status).tally
      SalesOrderStatus::ALL.index_with { counts.fetch(_1, 0) }
    end

    def self.filtered(relation, customer_tenant_id: nil, order_date_from: nil, order_date_to: nil)
      relation = relation.where(customer_tenant_id:) if customer_tenant_id
      relation = relation.where(order_date: order_date_from..) if order_date_from
      relation = relation.where(order_date: ..order_date_to) if order_date_to
      relation
    end

    def self.to_values(actor, orders)
      orders = orders.to_a
      lines = SalesOrderLine.where(sales_order_id: orders.map(&:id)).to_a
      allocated = Inventory::Allocation.quantities_for(actor, lines.map(&:id))
      lines = lines.group_by(&:sales_order_id)
      pending = CancellationReview.pending.where(sales_order_id: orders.map(&:id)).pluck(:sales_order_id).to_set
      orders.map do |order|
        SalesOrderValue.new(id: order.id, owner_tenant_id: order.owner_tenant_id, order_no: order.order_no,
          customer_tenant_id: order.customer_tenant_id, order_date: order.order_date, due_date: order.due_date,
          status: SalesOrderStatus.derive(order, lines.fetch(order.id, []), allocated:),
          cancellation_review_pending: pending.include?(order.id))
      end
    end

    def self.to_line_value(line, allocated)
      SalesOrderLineValue.new(**line.slice(*(SalesOrderLineValue.members - [ :allocated_quantity ]).map(&:to_s)).symbolize_keys,
        allocated_quantity: allocated.fetch(line.id))
    end
    private_class_method :filtered, :to_values, :to_line_value
  end
end
