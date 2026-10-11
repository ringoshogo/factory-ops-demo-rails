module Notifications
  # 外部の Webhook の受信（docs/adr/007 決定 5 の A-3）。テナントの表ではない
  class WebhookInboxEvent < ApplicationRecord
    self.table_name = "webhook_inbox_events"

    scope :unprocessed, -> { where(processed_at: nil) }
  end
end
