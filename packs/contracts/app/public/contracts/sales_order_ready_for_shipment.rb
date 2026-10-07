module Contracts
  # 出荷可能（受注 → 出荷）。全明細を全量引き当てた受注について出す。due_date は ISO 8601 の日付の文字列か空。
  # lines は { sales_order_line_id, purchase_order_line_id, item_id, quantity } の配列。
  # 発注明細 ID は、出荷が「出荷計上」で購買へ返すために運ぶ（docs/architecture/context-map.md「コンテキスト間の関係」）
  SalesOrderReadyForShipment = Event.define(:sales_order_id, :supplier_tenant_id, :buyer_tenant_id, :purchase_order_id,
    :due_date, :lines)
end
