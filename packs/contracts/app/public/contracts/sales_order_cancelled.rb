module Contracts
  # 受注取消（受注 → 購買）。受注側が、審査を経ずに自社の都合で受注を取り消した。
  # occurred_at は受注を取り消した時刻の ISO 8601 の文字列
  SalesOrderCancelled = Event.define(:purchase_order_id, :buyer_tenant_id, :supplier_tenant_id, :occurred_at)

  class SalesOrderCancelled
    # 発生の時刻を足す前に登録したジョブのペイロードは occurred_at を持たないので、空を足してから作り、受け手は受け取った時刻を書く。
    # new は全項目を求めたままにし、発行元が時刻を渡し忘れたら例外にする
    def self.from_payload(payload) = super({ "occurred_at" => nil }.merge(payload))
  end
end
