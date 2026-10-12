module Notifications
  # Action Mailer の配送の方法。組み立てたメールを Provider::Message に写して、設定の送信先へ渡す。
  # 送信先の応答は response に残し、ジョブが提供元のメッセージ ID を読む。失敗は Provider の例外のまま上げる
  class Delivery
    CUSTOM_ARGS_HEADER = "X-Notification-Custom-Args"

    attr_reader :settings, :response

    def initialize(settings)
      @settings = settings
    end

    def deliver!(mail)
      custom_args = JSON.parse(mail[CUSTOM_ARGS_HEADER].value)
      @response = Provider.current.deliver(Provider::Message.new(from: mail.from.first, to: mail.to, subject: mail.subject,
        body: mail.body.decoded, custom_args:))
    end
  end
end
