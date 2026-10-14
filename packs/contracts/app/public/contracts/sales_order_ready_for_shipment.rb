module Contracts
  # 出荷可能（受注 → 出荷）。全明細を全量引き当てた受注について出す。due_date は ISO 8601 の日付の文字列か空。
  # lines は { sales_order_line_id, purchase_order_line_id, item_id, quantity } の配列。
  # 発注明細 ID は、出荷が「出荷計上」で購買へ返すために運ぶ（docs/architecture/context-map.md「コンテキスト間の関係」）。
  # 受注番号は、出荷が出荷依頼の一覧を受注番号で並べるために運ぶ
  SalesOrderReadyForShipment = Event.define(:sales_order_id, :sales_order_no, :supplier_tenant_id, :buyer_tenant_id, :purchase_order_id,
    :due_date, :lines)

  class SalesOrderReadyForShipment
    # 受注番号を足す前に登録したジョブのペイロードは sales_order_no を持たないので、空を足してから作る。
    # new は全項目を求めたままにし、発行元が受注番号を渡し忘れたら例外にする
    def self.from_payload(payload) = super({ "sales_order_no" => nil }.merge(payload))
  end
end
