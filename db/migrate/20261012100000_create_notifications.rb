class CreateNotifications < ActiveRecord::Migration[8.1]
  include TenantTable

  # 確実な送信の送信記録と、Webhook の受信の表（docs/architecture/data-model.md「通知（`notifications`）」、docs/adr/007 決定 5）
  def change
    create_tenant_table :email_deliveries, comment: "[通知] 確実な送信の送信記録。通知キーごとに 1 行で、状況は時刻列から導出する" do |t|
      t.string :notification_key, null: false
      t.string :kind, null: false
      # 宛先はユーザー ID だけを持ち、メールアドレスは送るときに自社の users から引く
      t.uuid :recipient_user_ids, array: true, null: false, default: []
      # 本文に差し込む値。再送でも同じ本文を作れるよう、送信記録に持つ。メールアドレスは入れない
      t.jsonb :params, null: false, default: {}
      t.integer :attempts, null: false, default: 0
      t.string :provider_message_id
      t.datetime :accepted_at
      t.datetime :delivered_at
      t.datetime :bounced_at
      t.datetime :dropped_at
      t.datetime :failed_at
      t.string :failure_reason
      t.timestamps

      # 同じ通知の送信記録は 1 件。同じイベントが 2 回届いても、2 回目の deliver_critical は行を足さない
      t.index [ :owner_tenant_id, :notification_key ], unique: true
      t.check_constraint "(failed_at IS NULL) = (failure_reason IS NULL)", name: "email_deliveries_failure_reason"
    end

    # 届いた時点ではテナントが決まらないので、テナントの表にしない。主キーは他の表と同じく UUIDv7 にする
    create_table :webhook_inbox_events, id: :uuid, default: -> { "uuidv7()" },
      comment: "[通知] 外部の Webhook の受信。提供元のイベント ID ごとに 1 行で、メールアドレスを除いて生のまま残す" do |t|
      t.string :provider, null: false
      t.string :provider_event_id, null: false
      t.datetime :received_at, null: false
      t.jsonb :payload, null: false
      t.datetime :processed_at
      t.timestamps

      # 提供元が同じイベントを送り直しても 1 行にする
      t.index [ :provider, :provider_event_id ], unique: true
      # 未処理の行を拾う定期のジョブと、処理済みを消すジョブが使う
      t.index :received_at, where: "processed_at IS NULL", name: "index_webhook_inbox_events_unprocessed"
      t.index :processed_at, where: "processed_at IS NOT NULL", name: "index_webhook_inbox_events_processed"
    end
  end
end
