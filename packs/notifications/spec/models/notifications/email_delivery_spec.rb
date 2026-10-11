require "rails_helper"

# 送信記録の状況の導出と、Webhook の結果の書き方（docs/architecture/data-model.md「通知（`notifications`）」）
RSpec.describe Notifications::EmailDelivery do
  let(:tenant) { FactoryBot.create(:tenant).id }
  let(:at) { Time.zone.parse("2026-10-12 10:00") }

  def delivery(**attributes)
    Tenancy.with_tenant(tenant) { FactoryBot.create(:email_delivery, **attributes) }
  end

  it "状況を、失敗・不達・配信済・受付済・待機中の優先順で導出する" do
    expect(delivery.status).to eq(:pending)
    expect(delivery(accepted_at: at).status).to eq(:accepted)
    expect(delivery(accepted_at: at, delivered_at: at).status).to eq(:delivered)
    expect(delivery(accepted_at: at, delivered_at: at, bounced_at: at).status).to eq(:undelivered)
    expect(delivery(accepted_at: at, dropped_at: at).status).to eq(:undelivered)
    expect(delivery(accepted_at: at, bounced_at: at, failed_at: at, failure_reason: "http_400").status).to eq(:failed)
  end

  it "Webhook の結果は、時刻列が空のときだけ書く" do
    record = delivery(accepted_at: at)

    Tenancy.with_tenant(tenant) do
      record.record_event!("delivered", at + 1.minute)
      record.record_event!("delivered", at + 2.minutes)
      record.record_event!("bounce", at + 3.minutes)
      record.record_event!("dropped", at + 4.minutes)
    end

    Tenancy.with_tenant(tenant) { record.reload }
    expect(record.slice(:delivered_at, :bounced_at, :dropped_at).values).to eq([ at + 1.minute, at + 3.minutes, at + 4.minutes ])
  end

  it "時刻列を持たない種類のイベントは書かない" do
    record = delivery(accepted_at: at)

    Tenancy.with_tenant(tenant) do
      record.record_event!("open", at)
      expect(record.reload.slice(:delivered_at, :bounced_at, :dropped_at).values).to all(be_nil)
      # 同じ準備で、時刻列を持つ種類なら書く（対照）
      record.record_event!("delivered", at)
      expect(record.reload.delivered_at).to eq(at)
    end
  end

  it "失敗の時刻と理由は、揃って空か揃って埋まる" do
    expect { delivery(failed_at: at) }.to raise_error(ActiveRecord::StatementInvalid, /email_deliveries_failure_reason/)
  end
end
