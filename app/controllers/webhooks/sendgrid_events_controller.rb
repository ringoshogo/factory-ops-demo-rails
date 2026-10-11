module Webhooks
  # SendGrid のイベント Webhook の受け口（docs/adr/007 決定 5 の A-3）。署名で認証し、セッションを読まない。
  # 受け取ったイベントを受信の表に書いたらすぐ 200 を返し、処理はジョブに回す
  class SendgridEventsController < ApplicationController
    SIGNATURE_HEADER = "X-Twilio-Email-Event-Webhook-Signature"
    TIMESTAMP_HEADER = "X-Twilio-Email-Event-Webhook-Timestamp"

    def create
      result = Notifications::Inbox.receive_sendgrid(request.raw_post,
        signature: request.headers[SIGNATURE_HEADER], timestamp: request.headers[TIMESTAMP_HEADER])
      head({ ok: :ok, unauthorized: :unauthorized, bad_request: :bad_request }.fetch(result))
    end
  end
end
