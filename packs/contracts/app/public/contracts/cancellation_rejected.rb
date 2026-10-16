module Contracts
  # 取消却下（受注 → 購買）。受注側の担当者が審査を却下したか、依頼が届いた時点で受注が出荷済みか取消済だった。
  # occurred_at は審査を決着させた時刻か、自動で却下した時刻の ISO 8601 の文字列
  CancellationRejected = Event.define(:cancellation_request_id, :purchase_order_id, :buyer_tenant_id, :supplier_tenant_id, :occurred_at)

  class CancellationRejected
    # 発生の時刻を足す前に登録したジョブのペイロードは occurred_at を持たないので、空を足してから作り、受け手は受け取った時刻を書く。
    # new は全項目を求めたままにし、発行元が時刻を渡し忘れたら例外にする
    def self.from_payload(payload) = super({ "occurred_at" => nil }.merge(payload))
  end
end
