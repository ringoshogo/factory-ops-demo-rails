module Contracts
  # 取消承認（受注 → 購買）。受注側の担当者が審査を承認し、受注を取り消した。occurred_at は審査を決着させた時刻の ISO 8601 の文字列
  CancellationApproved = Event.define(:cancellation_request_id, :purchase_order_id, :buyer_tenant_id, :supplier_tenant_id, :occurred_at)

  class CancellationApproved
    # 発生の時刻を足す前に登録したジョブのペイロードは occurred_at を持たないので、空を足してから作り、受け手は受け取った時刻を書く。
    # new は全項目を求めたままにし、発行元が時刻を渡し忘れたら例外にする
    def self.from_payload(payload) = super({ "occurred_at" => nil }.merge(payload))
  end
end
