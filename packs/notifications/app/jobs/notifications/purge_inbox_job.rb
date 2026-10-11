module Notifications
  # 処理を終えた Webhook の受信を 30 日で消す（docs/adr/007 決定 5 の A-3）。受信の表は RLS の外にあるので、長く残さない
  class PurgeInboxJob < ApplicationJob
    RETENTION = 30.days

    def perform
      WebhookInboxEvent.where(processed_at: ...RETENTION.ago).in_batches(of: 1000).delete_all
    end
  end
end
