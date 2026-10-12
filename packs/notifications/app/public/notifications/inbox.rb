require "base64"
require "openssl"

module Notifications
  # Webhook の受け口（docs/adr/007 決定 5 の A-3）。署名と時刻を確かめ、イベントを受信の表に書いて、処理のジョブを登録する
  module Inbox
    SENDGRID = "sendgrid"

    # 署名の時刻と受け取った時刻の差の上限。古い署名付きの要求を送り直されても受け付けない。
    # SendGrid は再送のたびに時刻を付け直して署名するので、再送はこの幅に入る
    SIGNATURE_TOLERANCE = 10.minutes

    # 受信の表に残す項目。宛先のメールアドレス（email）と、不達の理由のようにアドレスを含みうる自由記述は残さない
    STORED_KEYS = %w[sg_event_id sg_message_id event timestamp tenant_id email_delivery_id].freeze

    # SendGrid の署名付きイベント Webhook を受け取る。:unauthorized・:bad_request・:ok のどれかを返す。
    # 署名は「時刻の文字列 + 本文の生のバイト列」の SHA-256 に対する ECDSA で、公開鍵は Base64 の DER である
    def self.receive_sendgrid(raw_body, signature:, timestamp:, now: Time.current)
      return :unauthorized unless sendgrid_signature_valid?(raw_body, signature:, timestamp:, now:)

      events = JSON.parse(raw_body)
      return :bad_request unless events.is_a?(Array) && events.all?(Hash)

      rows = events.filter_map do |event|
        event_id = event["sg_event_id"]
        next unless event_id.is_a?(String) && event_id.present?

        { provider: SENDGRID, provider_event_id: event_id, received_at: now, payload: event.slice(*STORED_KEYS) }
      end
      inserted = rows.any? ? WebhookInboxEvent.insert_all(rows, unique_by: %i[provider provider_event_id], returning: :id) : nil
      ProcessInboxJob.perform_later if inserted&.rows&.any?
      :ok
    rescue JSON::ParserError
      :bad_request
    end

    def self.sendgrid_signature_valid?(raw_body, signature:, timestamp:, now:)
      public_key = Rails.configuration.x.notifications.sendgrid_webhook_public_key
      return false if public_key.blank? || signature.blank? || !timestamp.to_s.match?(/\A\d+\z/)
      return false if (now.to_i - timestamp.to_i).abs > SIGNATURE_TOLERANCE

      key = OpenSSL::PKey::EC.new(Base64.strict_decode64(public_key))
      key.verify("SHA256", Base64.strict_decode64(signature), "#{timestamp}#{raw_body}")
    rescue ArgumentError, OpenSSL::PKey::PKeyError
      false
    end
    private_class_method :sendgrid_signature_valid?
  end
end
