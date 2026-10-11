require "rails_helper"

# Webhook の受信の処理（docs/adr/007 決定 5 の A-3）。custom_args のテナントで送信記録の時刻列を空のときだけ書き、
# 処理した行に processed_at を書く。送信記録の見つからないイベントも処理済みにして捨てる
RSpec.describe Notifications::ProcessInboxJob do
  let!(:tenant) { FactoryBot.create(:tenant).id }
  let!(:delivery) { Tenancy.with_tenant(tenant) { FactoryBot.create(:email_delivery, accepted_at: Time.current) } }
  let(:at) { Time.zone.at(1_791_000_000) }

  def inbox(event, **payload)
    Notifications::WebhookInboxEvent.create!(provider: "sendgrid", provider_event_id: "ev-#{SecureRandom.hex(6)}",
      received_at: Time.current, payload: { "event" => event, "timestamp" => at.to_i, "tenant_id" => tenant,
        "email_delivery_id" => delivery.id }.merge(payload.transform_keys(&:to_s)))
  end

  def reloaded = Tenancy.with_tenant(tenant) { delivery.reload }

  it "配信・不達・拒否のイベントを、送信記録の時刻列に書き、行を処理済みにする" do
    rows = [ inbox("delivered"), inbox("bounce", timestamp: at.to_i + 60), inbox("dropped", timestamp: at.to_i + 120) ]

    described_class.perform_now

    expect(reloaded.slice(:delivered_at, :bounced_at, :dropped_at).values).to eq([ at, at + 60, at + 120 ])
    expect(rows.map { _1.reload.processed_at }).to all(be_present)
  end

  it "処理を 2 回流しても、時刻列は最初の 1 回だけ書かれる" do
    inbox("delivered")
    described_class.perform_now
    inbox("delivered", timestamp: at.to_i + 600)
    described_class.perform_now

    expect(reloaded.delivered_at).to eq(at)
    expect(Notifications::WebhookInboxEvent.unprocessed).to be_empty
  end

  it "処理済みの行は読み直さない" do
    row = inbox("delivered")
    row.update!(processed_at: Time.current)

    described_class.perform_now

    expect(reloaded.delivered_at).to be_nil
  end

  it "送信記録が見つからない・テナントか送信記録の ID が UUID でない・時刻列の無い種類のイベントは、書かずに処理済みにする" do
    rows = [
      inbox("delivered", email_delivery_id: SecureRandom.uuid),
      inbox("delivered", tenant_id: "not-a-uuid"),
      inbox("delivered", email_delivery_id: nil),
      inbox("open")
    ]

    described_class.perform_now

    expect(reloaded.slice(:delivered_at, :bounced_at, :dropped_at).values).to all(be_nil)
    expect(rows.map { _1.reload.processed_at }).to all(be_present)
    # 同じ送信記録を指す配信のイベントなら書く（対照）
    inbox("delivered")
    described_class.perform_now
    expect(reloaded.delivered_at).to eq(at)
  end

  it "別のテナントの送信記録は、イベントの宛先のテナントからは書けない" do
    other = FactoryBot.create(:tenant).id
    inbox("delivered", tenant_id: other)

    described_class.perform_now

    expect(reloaded.delivered_at).to be_nil
  end

  it "時刻が整数でなければ、受け取った時刻を使う" do
    row = inbox("delivered", timestamp: "x")

    described_class.perform_now

    expect(reloaded.delivered_at).to eq(row.received_at)
  end

  it "1 回のトランザクションで取る件数を超える行も、1 回の実行で処理し終える" do
    stub_const("#{described_class}::BATCH_SIZE", 2)
    5.times { inbox("open") }

    described_class.perform_now

    expect(Notifications::WebhookInboxEvent.unprocessed).to be_empty
  end
end
