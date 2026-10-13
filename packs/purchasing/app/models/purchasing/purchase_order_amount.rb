module Purchasing
  # 発注の合計金額（税抜）を、明細の数量と受注確定で写した単価の積の和で返す SQL の式。単価の写しの無い明細（受注確定の前）が
  # 1 つでもあれば空にし、一部の合計を出さない。公開 API の表示と並べ替えが、この式だけを読む
  # （docs/architecture/graphql-schema.md「ページングと N+1」）
  module PurchaseOrderAmount
    # 単価は bigint の上限まで入りうるので、積を numeric で計算する。bigint のままでは桁あふれで SQL のエラーになる
    def self.expression
      lines = PurchaseOrderLine.arel_table
      quantity = Arel::Nodes::NamedFunction.new("CAST", [ lines[:quantity].as(Arel.sql("numeric")) ])
      total = Arel::Nodes::Case.new
        .when(Arel::Nodes::NamedFunction.new("bool_or", [ lines[:confirmed_unit_price].eq(nil) ])).then(nil)
        .else(Arel::Nodes::Sum.new([ Arel::Nodes::Multiplication.new(quantity, lines[:confirmed_unit_price]) ]))
      Arel::Nodes::Grouping.new(PurchaseOrderLine.where(lines[:purchase_order_id].eq(PurchaseOrder.arel_table[:id])).select(total).arel)
    end
  end
end
