module Inventory
  # 受注明細の引当・解除・消費（docs/architecture/context-map.md「コンテキスト間の関係」の受注 → 在庫・出荷 → 在庫）。
  # 呼ぶ側のトランザクションの中で、在庫（item_id 昇順）→ 引当（受注明細 ID 順）の順に行ロックを取る。
  # 呼ぶ側は、その前に受注 → 受注明細の順にロックを取っておく（docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
  module Allocation
    # lines は { sales_order_line_id:, item_id:, quantity: } の配列。各明細の未引当の量を、有効在庫の範囲で引き当てる。
    # 解除・消費した明細は引き当て直さない。受注明細 ID ごとの引当数量を返す
    def self.allocate(actor, lines)
      stocks = Stock.lock_for(actor.tenant_id, lines.map { _1[:item_id] })
      allocations = locked_allocations(actor, lines.map { _1[:sales_order_line_id] })
      lines.sort_by { _1[:sales_order_line_id] }.each do |line|
        allocation = allocations[line[:sales_order_line_id]]
        next if allocation && !allocation.active?

        stock = stocks.fetch(line[:item_id])
        take = [ line[:quantity] - allocation&.quantity.to_i, stock.available ].min
        next unless take.positive?

        allocation ||= StockAllocation.new(owner_tenant_id: actor.tenant_id, sales_order_line_id: line[:sales_order_line_id],
          item_id: line[:item_id], quantity: 0)
        allocation.update!(quantity: allocation.quantity + take)
        stock.move!("allocate", take, allocation:)
      end
      quantities_for(actor, lines.map { _1[:sales_order_line_id] })
    end

    # 受注の取消で引当を解除する。引当の無い明細は飛ばす。消費済み（出荷済み）の引当があれば何も変えず CONFLICT を返す
    def self.release(actor, sales_order_line_ids)
      move(actor, sales_order_line_ids, "deallocate", "released") { |allocations| allocations.any?(&:consumed?) }
    end

    # 出荷の計上で引当を消費し、現在庫と引当を減らす。引当の無い明細か active でない引当があれば何も変えず CONFLICT を返す
    def self.consume(actor, sales_order_line_ids)
      move(actor, sales_order_line_ids, "ship", "consumed") do |allocations|
        allocations.size != sales_order_line_ids.uniq.size || !allocations.all?(&:active?)
      end
    end

    # 受注明細 ID ごとの引当数量。解除した引当は数えず、引当の無い明細は 0 になる
    def self.quantities_for(actor, sales_order_line_ids)
      sales_order_line_ids.index_with(0).merge(active(actor).where(sales_order_line_id: sales_order_line_ids).group(:sales_order_line_id).sum(:quantity))
    end

    # 受注明細 ID ごとの引当数量を返す副問い合わせ。受注の状況の SQL の式が結ぶ（docs/adr/010-状況の導出をSQLの式1つにする.md）。
    # 条件は quantities_for と同じで、操作者の scope を掛けた後に SQL の文字列にするので、受け取る側は条件を外せない。
    # 引当の無い明細は行を持たない
    def self.active_quantities_sql(actor)
      SqlSubquery.of(active(actor).group(:sales_order_line_id).select(:sales_order_line_id, StockAllocation.arel_table[:quantity].sum.as("quantity")),
        sales_order_line_id: "sales_order_line_id", quantity: "quantity")
    end

    # 解除していない引当
    def self.active(actor) = Scope.call(actor, StockAllocation.all).where.not(status: "released")

    def self.move(actor, sales_order_line_ids, type, status)
      item_ids = Scope.call(actor, StockAllocation.all).where(sales_order_line_id: sales_order_line_ids).pluck(:item_id)
      stocks = Stock.lock_for(actor.tenant_id, item_ids)
      allocations = locked_allocations(actor, sales_order_line_ids).values
      return OperationResult.failure(:conflict) if yield(allocations)

      allocations.select(&:active?).each do |allocation|
        allocation.update!(status:)
        stocks.fetch(allocation.item_id).move!(type, allocation.quantity, allocation:)
      end
      OperationResult.success
    end

    def self.locked_allocations(actor, sales_order_line_ids)
      Scope.call(actor, StockAllocation.all).where(sales_order_line_id: sales_order_line_ids)
        .order(:sales_order_line_id).lock.index_by(&:sales_order_line_id)
    end
    private_class_method :active, :move, :locked_allocations
  end
end
