require "rails_helper"

# 確実な外部送信のジョブ（docs/adr/007 決定 5 の A-2）。送信記録の行をロックし、受け付けか失敗を書く。
# 429・5xx・タイムアウトは送信記録の試行回数を書いたトランザクションで登録し直し、使い切るか再試行しない失敗なら運用者に知らせる
RSpec.describe Notifications::CriticalDeliveryJob do
  include ActiveSupport::Testing::TimeHelpers

  let!(:tenant) { FactoryBot.create(:tenant).id }
  let!(:admin) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user, :admin, email: "admin-#{SecureRandom.hex(4)}@example.com") } }
  let!(:delivery) { Tenancy.with_tenant(tenant) { FactoryBot.create(:email_delivery, recipient_user_ids: [ admin.id ]) } }
  let(:events) { [] }
  let(:collector) { Struct.new(:events) { def emit(event) = events << event }.new(events) }

  around do |example|
    Rails.event.subscribe(collector)
    example.run
  ensure
    Rails.event.unsubscribe(collector)
  end

  # ジョブはテナントの中で作り、その外で実行する。実行のテナントは作った時点のテナントで開く（ApplicationJob）
  def run(executions: 0)
    job = Tenancy.with_tenant(tenant) { described_class.new(delivery.id) }
    job.executions = executions
    job.perform_now
    job
  end

  def reloaded = Tenancy.with_tenant(tenant) { delivery.reload }
  def failures = events.select { _1[:name] == "notification.delivery_failed" }.map { _1[:payload] }
  def retries = SolidQueue::Job.where(class_name: described_class.name, finished_at: nil).where("arguments LIKE ?", "%#{delivery.id}%")

  it "自社の users から引いた宛先へ送り、受け付けの時刻と提供元のメッセージ ID を書く" do
    run

    message = Notifications::FakeProvider.deliveries.sole
    expect([ message.to, message.subject ]).to eq([ [ admin.email ], "請求書が届きました（INV-000001）" ])
    expect(message.body).to include("INV-000001", "2026-10-12", "1100 円")
    expect(message.custom_args).to eq("tenant_id" => tenant, "email_delivery_id" => delivery.id)
    expect(reloaded.slice(:attempts, :failed_at).values).to eq([ 1, nil ])
    expect(reloaded.accepted_at).to be_present
    expect(reloaded.provider_message_id).to start_with("fake-")
  end

  # メトリクスの notification_acceptance_seconds の出どころ（docs/guides/config.md「メトリクス」）
  it "受け付けを書いた後に、送信記録を作ってから受け付けるまでのミリ秒を出す。失敗では出さない" do
    accepted = -> { events.select { _1[:name] == "notification.accepted" }.map { _1[:payload] } }
    Notifications::FakeProvider.fail_next(Notifications::Provider::TransientError.new("http_503"))
    run
    expect(accepted.()).to eq([])

    travel_to(reloaded.created_at + 90.5, with_usec: true) do
      run(executions: 1)
    end

    expect(accepted.()).to eq([ { kind: "received_invoice", delivery_id: delivery.id, attempts: 2, acceptance_ms: 90_500 } ])
  end

  it "受け付けの後にもう一度流しても、送らない" do
    run
    run

    expect(Notifications::FakeProvider.deliveries.size).to eq(1)
    expect(reloaded.attempts).to eq(1)
  end

  it "再試行しない失敗（400 など）は、失敗の時刻と理由を書き、運用者に知らせる" do
    Notifications::FakeProvider.fail_next(Notifications::Provider::PermanentError.new("http_400"))

    run

    expect(reloaded.slice(:failure_reason, :attempts, :accepted_at).values).to eq([ "http_400", 1, nil ])
    expect(reloaded.failed_at).to be_present
    expect(failures).to eq([ { kind: "received_invoice", delivery_id: delivery.id, reason: "http_400", attempts: 1 } ])
    expect(retries).to be_empty
  end

  it "失敗を書いた送信記録は、もう一度流しても送らない" do
    Notifications::FakeProvider.fail_next(Notifications::Provider::PermanentError.new("http_401"))
    run
    run

    expect(Notifications::FakeProvider.deliveries).to be_empty
    expect(reloaded.attempts).to eq(1)
  end

  it "5xx・タイムアウトは、試行回数を書いて、間隔を延ばして登録し直す" do
    Notifications::FakeProvider.fail_next(Notifications::Provider::TransientError.new("http_503"))

    travel_to(Time.zone.parse("2026-10-12 10:00")) { run(executions: 2) }

    expect(reloaded.slice(:attempts, :failed_at, :accepted_at).values).to eq([ 1, nil, nil ])
    retry_job = retries.sole
    expect(retry_job.arguments.slice("arguments", "executions")).to eq("arguments" => [ delivery.id ], "executions" => 3)
    # 3 回目の実行の間隔は 3 の 4 乗の 81 秒に、揺らぎ（最大 15%）と 2 秒を足した幅に入る
    expect(retry_job.scheduled_at - Time.zone.parse("2026-10-12 10:00")).to be_between(83, 83 + 81 * 0.15)
    expect(failures).to be_empty
  end

  it "429 は、応答が示した待ち時間の後に登録し直す" do
    Notifications::FakeProvider.fail_next(Notifications::Provider::RateLimited.new(wait: 120))

    travel_to(Time.zone.parse("2026-10-12 10:00")) { run }

    expect(retries.sole.scheduled_at).to eq(Time.zone.parse("2026-10-12 10:02"))
    expect(reloaded.attempts).to eq(1)
  end

  it "429 が待ち時間を示さなければ、5xx と同じく間隔を延ばす" do
    Notifications::FakeProvider.fail_next(Notifications::Provider::RateLimited.new)

    travel_to(Time.zone.parse("2026-10-12 10:00")) { run }

    expect(retries.sole.scheduled_at - Time.zone.parse("2026-10-12 10:00")).to be_between(3, 3 * 1.15)
  end

  it "再試行を 8 回で使い切ったら、失敗の時刻と理由を書き、運用者に知らせる。429 と 5xx を合わせて数える" do
    Notifications::FakeProvider.fail_next(Notifications::Provider::RateLimited.new(wait: 10))
    run(executions: 6)
    expect(retries.count).to eq(1)

    Notifications::FakeProvider.fail_next(Notifications::Provider::TransientError.new("Net::ReadTimeout"))
    run(executions: 7)

    expect(reloaded.failure_reason).to eq("retries_exhausted:Net::ReadTimeout")
    expect(reloaded.attempts).to eq(2)
    expect(failures.map { _1[:reason] }).to eq([ "retries_exhausted:Net::ReadTimeout" ])
    expect(retries.count).to eq(1)
  end

  it "宛先が 1 人も引けなければ、送らずに失敗にする" do
    Tenancy.with_tenant(tenant) { delivery.update!(recipient_user_ids: [ SecureRandom.uuid ]) }

    run

    expect(Notifications::FakeProvider.deliveries).to be_empty
    expect(reloaded.failure_reason).to eq("no_recipients")
  end

  it "送信記録が無ければ何もしない" do
    Tenancy.with_tenant(tenant) { delivery.delete }

    expect { run }.not_to raise_error
    expect(Notifications::FakeProvider.deliveries).to be_empty
  end
end
