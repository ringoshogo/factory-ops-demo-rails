require "rails_helper"

# 送信と Webhook の処理の競合（docs/adr/007 決定 2「ジョブが行を取って処理する」）。
# 同じ送信記録の 2 つの送信のジョブは送信記録の行ロックで直列になり、後のジョブは受け付けを見て送らない。
# inbox の処理を 2 つ同時に流しても、同じ行を 2 回は取らない
RSpec.describe "送信記録と受信の表のロック" do
  self.use_transactional_tests = false

  let!(:tenant) { FactoryBot.create(:tenant).id }
  let!(:admin) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user, :admin) } }
  let!(:delivery) do
    Tenancy.with_tenant(tenant) { FactoryBot.create(:email_delivery, notification_key: "received_invoice:#{SecureRandom.uuid}", recipient_user_ids: [ admin.id ]) }
  end
  let(:inbox_ids) { [] }

  # delete_owned_rows が開いたままのトランザクションを閉じさせてから、受信の表の行を消す。先に消すと、行ロックを待ったまま止まる
  after do
    delete_owned_rows([ tenant ], %w[email_deliveries])
    Notifications::WebhookInboxEvent.where(id: inbox_ids).delete_all
  end

  it "Notifications::CriticalDeliveryJob.perform は、同じ送信記録の 2 回目の実行を、1 回目のコミットまで待たせて送らせない" do
    first, second = 2.times.map { Tenancy.with_tenant(tenant) { Notifications::CriticalDeliveryJob.new(delivery.id) } }

    _, release, holder = hold_open(tenant) { first.perform_now }
    waiter = in_thread(tenant) { second.perform_now }

    expect(blocked_on_lock?(waiter, by: holder)).to be(true)
    commit(release, holder)
    finish(waiter)
    expect(Notifications::FakeProvider.deliveries.size).to eq(1)
    expect(Tenancy.with_tenant(tenant) { delivery.reload.attempts }).to eq(1)
  end

  it "Notifications::ProcessInboxJob.process_batch は、別の処理が取った行を待たずに飛ばし、どの行も 1 回だけ処理する" do
    stub_const("Notifications::ProcessInboxJob::BATCH_SIZE", 1)
    # 2 つの行は別々の送信記録を指す。同じ送信記録なら、受信の表ではなく送信記録の行ロックで待つ
    deliveries = [ delivery, Tenancy.with_tenant(tenant) { FactoryBot.create(:email_delivery, notification_key: "received_invoice:#{SecureRandom.uuid}") } ]
    deliveries.each_with_index do |target, index|
      inbox_ids << Notifications::WebhookInboxEvent.create!(provider: "sendgrid", provider_event_id: SecureRandom.uuid,
        received_at: Time.current + index, payload: { "event" => "delivered", "timestamp" => 1_791_000_000 + index, "tenant_id" => tenant,
          "email_delivery_id" => target.id }).id
    end

    taken, release, holder = hold_open(tenant) { Notifications::ProcessInboxJob.new.send(:process_batch) }
    waiter = in_thread(tenant) { Notifications::ProcessInboxJob.new.send(:process_batch) }

    expect(blocked_on_lock?(waiter, by: holder)).to be(false)
    expect([ taken, finish(waiter) ]).to eq([ 1, 1 ])
    commit(release, holder)
    expect(Notifications::WebhookInboxEvent.where(id: inbox_ids, processed_at: nil)).to be_empty
    expect(Tenancy.with_tenant(tenant) { deliveries.map { _1.reload.delivered_at } })
      .to eq([ Time.zone.at(1_791_000_000), Time.zone.at(1_791_000_001) ])
  end

  it "Notifications::ProcessInboxJob.apply は、同じ送信記録を指す別の行の処理を送信記録のロックで待たせ、先に書いた時刻を残す" do
    stub_const("Notifications::ProcessInboxJob::BATCH_SIZE", 1)
    2.times do |index|
      inbox_ids << Notifications::WebhookInboxEvent.create!(provider: "sendgrid", provider_event_id: SecureRandom.uuid,
        received_at: Time.current + index, payload: { "event" => "delivered", "timestamp" => 1_791_000_000 + index, "tenant_id" => tenant,
          "email_delivery_id" => delivery.id }).id
    end

    _, release, holder = hold_open(tenant) { Notifications::ProcessInboxJob.new.send(:process_batch) }
    waiter = in_thread(tenant) { Notifications::ProcessInboxJob.new.send(:process_batch) }

    expect(blocked_on_lock?(waiter, by: holder)).to be(true)
    commit(release, holder)
    finish(waiter)
    expect(Notifications::WebhookInboxEvent.where(id: inbox_ids, processed_at: nil)).to be_empty
    expect(Tenancy.with_tenant(tenant) { delivery.reload.delivered_at }).to eq(Time.zone.at(1_791_000_000))
  end
end
