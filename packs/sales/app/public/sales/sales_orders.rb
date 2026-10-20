module Sales
  # 受注側が自社の受注を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）。
  # 状況と合計金額は、行と一緒に SalesOrderStatus と SalesOrderAmount の SQL の式で読む。明細の引当数量は、在庫の Inventory::Allocation から受注明細 ID ごとにまとめて得る
  module SalesOrders
    # 状況の一覧。GraphQL の enum が写すので、値を作る式との一致を確かめた一覧と同じオブジェクトを出す
    STATUSES = SalesOrderStatus::ALL

    # order_by は { field:, direction: } の配列で、1 つ目の列から順に並べる。空なら作った順の新しいものから並べる。
    # filter は得意先と、両端を含む受注日の範囲と、状況で絞る。状況の空の配列は 0 件で、nil なら絞らない
    def self.list(actor, first:, after:, order_by: [], filter: {})
      status = SalesOrderStatus.expression(actor)
      Page.of(filtered(Scope.sales_orders(actor, :own), status, **filter), first:, after:,
        sort: Page::Sort.of(order_by, order_columns(actor, status)), columns: columns(status)) { to_values(_1) }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      to_values(with_status(actor, Scope.sales_orders(actor, :own).where(id:))).first
    end

    # 受注 ID ごとの受注。見えない ID は含まない
    def self.by_ids(actor, ids)
      to_values(with_status(actor, Scope.sales_orders(actor, :own).where(id: ids))).index_by(&:id)
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

    # いまのテナントの受注の ID ごとの受注番号（rake タスク read_models:rebuild が、出荷依頼の受注番号の写しを作り直すために読む）。
    # 操作者のいない入口なので、テナントの設定を求め、所有テナントを明示して読む。取引先の受注は RLS に任せると見えうるからである
    # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
    def self.order_numbers
      Tenancy.require_tenant!
      SalesOrder.where(owner_tenant_id: Current.tenant_id).pluck(:id, :order_no).to_h
    end

    # 状況ごとの受注の件数。受注一覧の状況の絞り込みと同じ式で GROUP BY して数え、取消済を含む 7 つの状況をすべて持つ（0 件の状況も返す）
    def self.count_by_status(actor)
      counts = Scope.sales_orders(actor, :own).group(SalesOrderStatus.expression(actor)).count
      SalesOrderStatus::ALL.index_with { counts.fetch(_1.to_s, 0) }
    end

    # 並べてよい列（docs/architecture/graphql-schema.md「ページングと N+1」）。伝票番号は桁をそろえた文字列なので、文字列の順が番号の順になる。
    # 得意先の名前は取引関係の公開 API の副問い合わせから引き、状況は業務の進み順の位置で並べる
    def self.order_columns(actor, status)
      orders = SalesOrder.arel_table
      { order_no: [ orders[:order_no], :string ],
        order_date: [ orders[:order_date], :date ],
        due_date: [ orders[:due_date], :date ],
        customer_name: [ Partnerships::Directory.tenant_names_sql(actor).lookup(:name, :tenant_id, orders[:customer_tenant_id]), :string ],
        total_amount: [ SalesOrderAmount.expression, :decimal ],
        status: [ Page::Sort.rank(status, SalesOrderStatus::SORT_ORDER), :integer ] }
    end

    # 行と一緒に読む状況と合計金額の式
    def self.columns(status) = [ status.as("status"), SalesOrderAmount.expression.as("total_amount") ]

    def self.with_status(actor, relation) = relation.select(SalesOrder.arel_table[Arel.star], *columns(SalesOrderStatus.expression(actor)))

    # statuses の空の配列は、Arel の In が 1=0 にするので 0 件になる（activerecord 8.1 の Arel::Visitors::ToSql#visit_Arel_Nodes_In）
    def self.filtered(relation, status, customer_tenant_id: nil, order_date_from: nil, order_date_to: nil, statuses: nil)
      relation = relation.where(customer_tenant_id:) if customer_tenant_id
      relation = relation.where(order_date: order_date_from..) if order_date_from
      relation = relation.where(order_date: ..order_date_to) if order_date_to
      relation = relation.where(status.in(statuses.map(&:to_s))) unless statuses.nil?
      relation
    end

    # orders は状況と合計金額の式を status・total_amount の別名で読んだ受注。合計は numeric で読むので、整数に戻す
    def self.to_values(orders)
      orders = orders.to_a
      pending = CancellationReview.pending.where(sales_order_id: orders.map(&:id)).pluck(:sales_order_id).to_set
      orders.map do |order|
        SalesOrderValue.new(id: order.id, owner_tenant_id: order.owner_tenant_id, order_no: order.order_no,
          customer_tenant_id: order.customer_tenant_id, order_date: order.order_date, due_date: order.due_date,
          status: order["status"].to_sym, cancellation_review_pending: pending.include?(order.id), total_amount: order["total_amount"]&.to_i)
      end
    end

    def self.to_line_value(line, allocated)
      SalesOrderLineValue.new(**line.slice(*(SalesOrderLineValue.members - [ :allocated_quantity ]).map(&:to_s)).symbolize_keys,
        allocated_quantity: allocated.fetch(line.id))
    end
    private_class_method :order_columns, :columns, :with_status, :filtered, :to_values, :to_line_value
  end
end
