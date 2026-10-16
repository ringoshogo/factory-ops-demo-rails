module Contracts
  # 出荷計上（出荷 → 購買）。shipped_on は ISO 8601 の日付の文字列。
  # lines は { sales_order_line_id, purchase_order_line_id, quantity } の配列。受注 ID と受注明細 ID は、読む受け手が無いが消さない。
  # 消すと、消す前に登録したジョブのペイロードを from_payload が読めなくなる。購買はこの 2 つを保存しない
  # （docs/architecture/data-model.md「イベントの受け口と冪等キー」）
  ShipmentPosted = Event.define(:shipment_id, :sales_order_id, :purchase_order_id, :supplier_tenant_id, :buyer_tenant_id,
    :shipped_on, :lines)
end
