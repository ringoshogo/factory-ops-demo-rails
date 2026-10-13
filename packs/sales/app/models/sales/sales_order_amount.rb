module Sales
  # 受注の合計金額（税抜）を、明細の数量と単価の積の和で返す SQL の式。単価の無い明細（品番照合待ち）が 1 つでもあれば空にし、
  # 一部の合計を出さない。公開 API の表示と並べ替えが、この式だけを読む（docs/architecture/graphql-schema.md「ページングと N+1」）
  module SalesOrderAmount
    # 単価は bigint の上限まで入りうるので、積を numeric で計算する。bigint のままでは桁あふれで SQL のエラーになる
    def self.expression
      lines = SalesOrderLine.arel_table
      quantity = Arel::Nodes::NamedFunction.new("CAST", [ lines[:quantity].as(Arel.sql("numeric")) ])
      total = Arel::Nodes::Case.new
        .when(Arel::Nodes::NamedFunction.new("bool_or", [ lines[:unit_price].eq(nil) ])).then(nil)
        .else(Arel::Nodes::Sum.new([ Arel::Nodes::Multiplication.new(quantity, lines[:unit_price]) ]))
      Arel::Nodes::Grouping.new(SalesOrderLine.where(lines[:sales_order_id].eq(SalesOrder.arel_table[:id])).select(total).arel)
    end
  end
end
