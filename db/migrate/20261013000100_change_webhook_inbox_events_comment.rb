# 受信の表の説明を、残す項目の規則（処理に使う項目だけを許した一覧で残す。docs/adr/007 決定 5 の A-3）に合わせる。
# 前の説明は「メールアドレスを除いて生のまま残す」で、読んだ人が自由記述の項目も残す形に戻しうる
class ChangeWebhookInboxEventsComment < ActiveRecord::Migration[8.1]
  def change
    change_table_comment :webhook_inbox_events,
      from: "[通知] 外部の Webhook の受信。提供元のイベント ID ごとに 1 行で、メールアドレスを除いて生のまま残す",
      to: "[通知] 外部の Webhook の受信。提供元のイベント ID ごとに 1 行で、処理に使う項目だけを残す"
  end
end
