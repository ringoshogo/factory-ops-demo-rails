module Notifications
  # 外部へのメールの登録口（docs/adr/007 決定 4）。外部へ作用するジョブは、このファイルからだけ登録する。
  # カスタム Cop FactoryOps/ExternalEffectEnqueue が、ほかのファイルからの登録を落とす
  module Email
    # 確実な送信（A-2）。呼び出し元の業務のトランザクションの中で呼び、送信記録とジョブを業務データと一緒に確定させる。
    # 通知キーは所有テナントの中で一意で、同じキーの 2 回目は送信記録もジョブも足さない
    def self.deliver_critical(kind_name, key:, params:)
      kind = Catalog.fetch(kind_name, guarantee: :critical)
      values = Catalog.validate_params!(kind, params)
      # テナントは Tenancy.with_tenant のトランザクションの中にだけあるので、テナントがあれば業務のトランザクションの中にいる
      Tenancy.require_tenant!

      inserted = EmailDelivery.insert({ owner_tenant_id: Current.tenant_id, notification_key: key, kind: kind.name.to_s,
        recipient_user_ids: Partnerships::Recipients.admin_ids, params: values },
        unique_by: %i[owner_tenant_id notification_key], returning: :id)
      email_delivery_id = inserted.rows.first&.first or return

      CriticalDeliveryJob.perform_later(email_delivery_id)
    end

    # 撃ちっぱなしの送信（B-1）。送信記録を作らず、ジョブはコミットの後に登録される
    def self.deliver_best_effort(kind_name, params:)
      kind = Catalog.fetch(kind_name, guarantee: :best_effort)
      Tenancy.require_tenant!
      BestEffortMailJob.perform_later(kind.name.to_s, Catalog.validate_params!(kind, params))
    end

    # 再送の操作。since 以降に失敗した確実な送信の failed_at を空に戻し、同じ送信記録のジョブを登録し直す。
    # 新しい送信記録は作らない。送信記録が残っていることが、ジョブを拾い直せる根拠だからである（docs/adr/007 決定 2）。
    # 運用者は lib/tasks/notifications.rake から、テナントを明示して呼ぶ。登録し直した件数を返す
    def self.redeliver_failed(since:)
      Tenancy.require_tenant!
      ApplicationRecord.transaction do
        EmailDelivery.where(failed_at: since..).where(accepted_at: nil).order(:id).lock.map do |delivery|
          delivery.update!(failed_at: nil, failure_reason: nil)
          CriticalDeliveryJob.perform_later(delivery.id)
        end.size
      end
    end
  end
end
