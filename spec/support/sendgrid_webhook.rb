require "base64"
require "openssl"

# SendGrid の署名付きイベント Webhook を、テストの鍵で署名して作る補助（docs/adr/007 決定 5 の A-3）。
# 公開鍵を config.x.notifications.sendgrid_webhook_public_key に入れ、example の後で元に戻す
module SendgridWebhookHelpers
  def self.included(group)
    group.let(:sendgrid_key) { OpenSSL::PKey::EC.generate("prime256v1") }
    group.around do |example|
      config = Rails.configuration.x.notifications
      previous = config.sendgrid_webhook_public_key
      config.sendgrid_webhook_public_key = Base64.strict_encode64(sendgrid_key.public_to_der)
      example.run
    ensure
      config.sendgrid_webhook_public_key = previous
    end
  end

  # [本文, 署名, 時刻] を返す。署名は「時刻の文字列 + 本文」の SHA-256 に対する ECDSA を Base64 にしたもの
  def signed_sendgrid_events(events, at: Time.current, key: sendgrid_key)
    body = events.to_json
    timestamp = at.to_i.to_s
    [ body, Base64.strict_encode64(key.sign("SHA256", "#{timestamp}#{body}")), timestamp ]
  end

  def sendgrid_event(**overrides)
    { "email" => "admin@example.com", "timestamp" => 1_791_000_000, "event" => "delivered",
      "sg_event_id" => "ev-#{SecureRandom.hex(6)}", "sg_message_id" => "msg-1.filter", "reason" => "550 admin@example.com",
      "tenant_id" => SecureRandom.uuid, "email_delivery_id" => SecureRandom.uuid }.merge(overrides.transform_keys(&:to_s))
  end
end
