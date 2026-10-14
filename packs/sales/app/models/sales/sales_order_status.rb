module Sales
  # 受注の状況を、受注の時刻列と明細、在庫の引当から優先順で導出する SQL の式
  # （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」、docs/adr/010-状況の導出をSQLの式1つにする.md）。
  # 公開 API の表示・絞り込み・件数と、取消の可否が、この式だけを読む
  module SalesOrderStatus
    # 導出の優先順に並べた 7 つの状況
    ALL = %i[cancelled inspected shipped awaiting_part_match allocated partially_allocated received].freeze
    # 状況で並べるときの業務の進み順。導出の優先順（ALL）とは別の一覧で、同じ状況の集まりを持つ
    SORT_ORDER = %i[awaiting_part_match received partially_allocated allocated shipped inspected cancelled].freeze

    # 引当数量は、在庫の公開 API が操作者の scope を掛けて返す、受注明細 ID ごとの有効な引当数量の副問い合わせを結ぶ。
    # 引当の無い明細は副問い合わせに行が無いので、外部結合して 0 と読む。受注明細は、所有テナントと受注の組の外部キーで受注と同じテナントに限られる
    def self.expression(actor)
      allocations = Inventory::Allocation.active_quantities_sql(actor)
      orders = SalesOrder.arel_table
      allocated = allocations.as("allocated")
      quantity = Arel::Nodes::NamedFunction.new("COALESCE", [ allocations.column(allocated, :allocated_quantity), Arel::Nodes.build_quoted(0) ])
      lines = SalesOrderLine.where(SalesOrderLine.arel_table[:sales_order_id].eq(orders[:id]))
      allocated_lines = lines.joins(SalesOrderLine.arel_table.join(allocated, Arel::Nodes::OuterJoin)
        .on(allocations.column(allocated, :line_id).eq(SalesOrderLine.arel_table[:id])).join_sources)
      line_quantity = SalesOrderLine.arel_table[:quantity]

      Arel::Nodes::Case.new
        .when(orders[:cancelled_at].not_eq(nil)).then("cancelled")
        .when(orders[:inspected_at].not_eq(nil)).then("inspected")
        .when(orders[:shipped_at].not_eq(nil)).then("shipped")
        .when(lines.where(item_id: nil).arel.exists).then("awaiting_part_match")
        .when(allocated_lines.where(quantity.lt(line_quantity)).arel.exists.not).then("allocated")
        .when(allocated_lines.where(quantity.gt(0)).arel.exists).then("partially_allocated")
        .else("received")
    end
  end
end
