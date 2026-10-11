module Notifications
  # Webhook の受信の処理（docs/adr/007 決定 5 の A-3）。未処理の行を FOR UPDATE SKIP LOCKED で取り、送信のときに付けた
  # custom_args のテナントで送信記録の時刻列を書く。同時に 2 つ動いても、同じ行を 2 回は取らない。
  # 受信のときと 1 分ごとの定期のジョブ（config/recurring.yml）の両方から登録する
  class ProcessInboxJob < ApplicationJob
    BATCH_SIZE = 100
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    def perform
      loop { break if process_batch < BATCH_SIZE }
    end

    private

    def process_batch
      ApplicationRecord.transaction do
        rows = WebhookInboxEvent.unprocessed.order(:received_at, :id).limit(BATCH_SIZE).lock("FOR UPDATE SKIP LOCKED").to_a
        rows.each { apply(_1) }
        rows.size
      end
    end

    # 送信記録の見つからないイベント（撃ちっぱなしの送信・他の環境の送信・記録に無い種類のイベント）は、処理済みにして捨てる
    def apply(row)
      payload = row.payload
      tenant_id, delivery_id, event = payload.values_at("tenant_id", "email_delivery_id", "event")
      if [ tenant_id, delivery_id ].all? { UUID.match?(_1.to_s) } && EmailDelivery::EVENT_COLUMNS.key?(event)
        Tenancy.with_tenant(tenant_id) { EmailDelivery.find_by(id: delivery_id)&.record_event!(event, occurred_at(row)) }
      end
      row.update!(processed_at: Time.current)
    end

    def occurred_at(row)
      timestamp = row.payload["timestamp"]
      timestamp.is_a?(Integer) ? Time.zone.at(timestamp) : row.received_at
    end
  end
end
