module Notifications
  # 確実な送信の送信記録（docs/architecture/data-model.md「通知（`notifications`）」）
  class EmailDelivery < TenantRecord
    self.table_name = "email_deliveries"

    # Webhook のイベントの種類と、書く時刻列
    EVENT_COLUMNS = { "delivered" => :delivered_at, "bounce" => :bounced_at, "dropped" => :dropped_at }.freeze

    # 状況を時刻列から優先順で導出する（data-model.md「通知（`notifications`）」）
    def status
      if failed_at then :failed
      elsif bounced_at || dropped_at then :undelivered
      elsif delivered_at then :delivered
      elsif accepted_at then :accepted
      else :pending
      end
    end

    # Webhook の結果は、時刻列が空のときだけ書く。同じイベントが 2 回処理されても、最初の時刻が残る
    def record_event!(event, at)
      column = EVENT_COLUMNS[event] or return
      update!(column => at) if self[column].nil?
    end
  end
end
