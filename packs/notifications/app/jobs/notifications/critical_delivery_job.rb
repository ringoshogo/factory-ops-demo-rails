module Notifications
  # 確実な外部送信（docs/adr/007 決定 5 の A-2）。送信記録の行をロックし、受け付けか失敗が書かれていれば何もしない。
  # 再試行は retry_on で例外を上げずに、送信記録の試行回数と失敗の時刻を書いたトランザクションの中で登録し直す。
  # 例外を上げると ApplicationJob のテナントのトランザクションが戻り、送信記録に何も残らないからである
  class CriticalDeliveryJob < ExternalEffectJob
    include ProviderRetry

    # 送信記録と同じトランザクションで登録する。待機中の送信記録を拾い直すものが無いので、ジョブを失うと誰も気づけない
    self.enqueue_after_transaction_commit = false
    external_effect :at_least_once
    queue_as :external_mail
    # 撃ちっぱなしのジョブと合わせて、SendGrid への同時の送信を 2 つまでにする（docs/adr/007 決定 7）
    limits_concurrency key: "sendgrid", group: "sendgrid", to: 2

    ATTEMPTS = 8

    def perform(email_delivery_id)
      delivery = EmailDelivery.lock.find_by(id: email_delivery_id) or return
      return if delivery.accepted_at || delivery.failed_at

      delivery.attempts += 1
      emails = Partnerships::Recipients.emails(delivery.recipient_user_ids).values
      return fail!(delivery, "no_recipients") if emails.empty?

      # 受け付けの後、accepted_at のコミットの前に落ちると 2 通届く。この隙間は受け入れる（docs/adr/007 決定 6 の C-2）
      mail = Mailer.with(to: emails, values: delivery.params,
        custom_args: { "tenant_id" => delivery.owner_tenant_id, "email_delivery_id" => delivery.id }).public_send(delivery.kind)
      mail.deliver_now
      delivery.update!(accepted_at: Time.current, provider_message_id: mail.delivery_method.response.message_id)
      Rails.event.notify("notification.accepted", kind: delivery.kind, delivery_id: delivery.id, attempts: delivery.attempts,
        acceptance_ms: ((delivery.accepted_at - delivery.created_at) * 1000).round)
    rescue Provider::PermanentError => error
      fail!(delivery, error.message)
    rescue Provider::RateLimited, Provider::TransientError => error
      return fail!(delivery, "retries_exhausted:#{error.message}") unless retries_left?

      delivery.save!
      retry_job(wait: retry_wait(error), error:)
    end

    private

    # 運用者に知らせる。ログとメトリクスの経路が、このイベントを警報にする。
    # 送信記録の ID は delivery_id と書く。filter_parameters の email が名前の一部に当たり、email_delivery_id は値が隠れる
    def fail!(delivery, reason)
      delivery.update!(failed_at: Time.current, failure_reason: reason)
      Rails.event.notify("notification.delivery_failed", kind: delivery.kind, delivery_id: delivery.id,
        reason:, attempts: delivery.attempts)
    end
  end
end
