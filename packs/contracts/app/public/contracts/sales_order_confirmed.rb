module Contracts
  # 受注確定（受注 → 購買）。lines は { purchase_order_line_id, item_name, unit_price } の配列で、unit_price は円の整数の文字列。
  # occurred_at は受注を確定した時刻の ISO 8601 の文字列。受注・受注明細・品目の ID は運ばない
  # （docs/architecture/data-model.md「購買（`purchasing`）」「イベントの受け口と冪等キー」）
  SalesOrderConfirmed = Event.define(:purchase_order_id, :buyer_tenant_id, :supplier_tenant_id, :lines, :occurred_at)

  class SalesOrderConfirmed
    # 発生の時刻を足す前に登録したジョブのペイロードは occurred_at を持たないので、空を足してから作り、受け手は受け取った時刻を書く。
    # new は全項目を求めたままにし、発行元が時刻を渡し忘れたら例外にする
    def self.from_payload(payload) = super({ "occurred_at" => nil }.merge(payload))
  end
end
