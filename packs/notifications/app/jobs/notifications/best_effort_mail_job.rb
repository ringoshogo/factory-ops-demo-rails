module Notifications
  # 撃ちっぱなしの送信（docs/adr/007 決定 5 の B-1）。送信記録を作らず、宛先は送るときに自社の admin から引く。
  # 429・5xx・タイムアウトを合わせて 3 回まで試し、使い切るか再試行しない失敗なら、警告のイベントを出して捨てる
  class BestEffortMailJob < ExternalEffectJob
    include ProviderRetry

    # 業務データが確定した後に登録する。失っても画面の一覧で業務は進むので、トランザクションと結び付けない
    self.enqueue_after_transaction_commit = true
    external_effect :best_effort
    queue_as :external_mail
    limits_concurrency key: "sendgrid", group: "sendgrid", to: 2

    ATTEMPTS = 3

    def perform(kind, values)
      emails = Partnerships::Recipients.emails(Partnerships::Recipients.admin_ids).values
      return drop!(kind, "no_recipients") if emails.empty?

      Mailer.with(to: emails, values:, custom_args: { "tenant_id" => Current.tenant_id }).public_send(kind).deliver_now
    rescue Provider::PermanentError => error
      drop!(kind, error.message)
    rescue Provider::RateLimited, Provider::TransientError => error
      retries_left? ? retry_job(wait: retry_wait(error), error:) : drop!(kind, "retries_exhausted:#{error.message}")
    end

    private

    # 運用者には知らせない。警告のイベントだけを残す
    def drop!(kind, reason)
      Rails.event.notify("notification.best_effort_dropped", kind:, reason:, attempts: executions)
    end
  end
end
