require "rails_helper"

# 処理を終えた Webhook の受信を 30 日で消す（docs/adr/007 決定 5 の A-3）
RSpec.describe Notifications::PurgeInboxJob do
  include ActiveSupport::Testing::TimeHelpers

  def inbox(processed_at:)
    Notifications::WebhookInboxEvent.create!(provider: "sendgrid", provider_event_id: SecureRandom.hex(6), received_at: Time.current,
      payload: {}, processed_at:)
  end

  it "処理から 30 日を過ぎた行だけを消し、未処理の行は残す" do
    travel_to(Time.zone.parse("2026-10-12 10:00")) do
      expired = inbox(processed_at: 30.days.ago - 1)
      kept = [ inbox(processed_at: 30.days.ago + 1), inbox(processed_at: nil) ]

      described_class.perform_now

      expect(Notifications::WebhookInboxEvent.where(id: [ expired, *kept ].map(&:id)).pluck(:id)).to match_array(kept.map(&:id))
    end
  end
end
