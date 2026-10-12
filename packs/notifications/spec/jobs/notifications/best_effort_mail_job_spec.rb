require "rails_helper"

# 撃ちっぱなしの送信のジョブ（docs/adr/007 決定 5 の B-1）。宛先は送るときに自社の admin から引き、
# 429・5xx・タイムアウトを合わせて 3 回まで試して、使い切ったら警告のイベントを出して捨てる
RSpec.describe Notifications::BestEffortMailJob do
  let!(:tenant) { FactoryBot.create(:tenant).id }
  let!(:admin) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user, :admin) } }
  let!(:member) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user) } }
  let(:events) { [] }
  let(:collector) { Struct.new(:events) { def emit(event) = events << event }.new(events) }

  around do |example|
    Rails.event.subscribe(collector)
    example.run
  ensure
    Rails.event.unsubscribe(collector)
  end

  def run(executions: 0)
    job = Tenancy.with_tenant(tenant) { described_class.new("new_sales_order", { "order_no" => "SO-000001" }) }
    job.executions = executions
    job.perform_now
  end

  def dropped = events.select { _1[:name] == "notification.best_effort_dropped" }.map { _1[:payload] }
  def retries = SolidQueue::Job.where(class_name: described_class.name, finished_at: nil).where("arguments LIKE ?", "%#{tenant}%")

  it "自社の admin へ送り、member には送らない" do
    run

    message = Notifications::FakeProvider.deliveries.sole
    expect([ message.to, message.subject, message.custom_args ])
      .to eq([ [ admin.email ], "新しい受注があります（SO-000001）", { "tenant_id" => tenant } ])
  end

  it "5xx は 3 回目までは登録し直し、使い切ったら警告のイベントを出して捨てる" do
    Notifications::FakeProvider.fail_next(Notifications::Provider::TransientError.new("http_502"))
    run(executions: 1)
    expect(retries.count).to eq(1)
    expect(dropped).to be_empty

    Notifications::FakeProvider.fail_next(Notifications::Provider::RateLimited.new(wait: 5))
    run(executions: 2)

    expect(retries.count).to eq(1)
    expect(dropped).to eq([ { kind: "new_sales_order", reason: "retries_exhausted:rate_limited", attempts: 3 } ])
  end

  it "再試行しない失敗は、登録し直さずに捨てる" do
    Notifications::FakeProvider.fail_next(Notifications::Provider::PermanentError.new("http_413"))

    run

    expect(retries).to be_empty
    expect(dropped).to eq([ { kind: "new_sales_order", reason: "http_413", attempts: 1 } ])
  end

  it "admin がいなければ送らずに捨てる" do
    Tenancy.with_tenant(tenant) { admin.update!(role: "member") }

    run

    expect(Notifications::FakeProvider.deliveries).to be_empty
    expect(dropped.map { _1[:reason] }).to eq([ "no_recipients" ])
  end
end
