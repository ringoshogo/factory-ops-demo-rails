require "rails_helper"
require_relative "../../../../../spec/support/sendgrid_webhook"

# Webhook の受け口（docs/adr/007 決定 5 の A-3）。署名と時刻を確かめ、提供元のイベント ID で重複を捨て、メールアドレスを残さない
RSpec.describe Notifications::Inbox do
  include SendgridWebhookHelpers

  let(:now) { Time.zone.parse("2026-10-12 10:00") }

  def receive(body, signature, timestamp, now: self.now)
    described_class.receive_sendgrid(body, signature:, timestamp:, now:)
  end

  # 受信の表とキューはテナントで絞れないので、example の前からある行を数えない
  let!(:existing) { [ Notifications::WebhookInboxEvent.pluck(:id), SolidQueue::Job.pluck(:id) ] }

  def rows = Notifications::WebhookInboxEvent.where.not(id: existing[0]).order(:provider_event_id).to_a
  def process_jobs = SolidQueue::Job.where(class_name: "Notifications::ProcessInboxJob", finished_at: nil).where.not(id: existing[1])

  it "署名の合うイベントを、残す項目だけにして書き、処理のジョブを登録する" do
    event = sendgrid_event(sg_event_id: "ev-1")

    expect(receive(*signed_sendgrid_events([ event ], at: now))).to eq(:ok)

    expect(rows.map { _1.slice(:provider, :provider_event_id, :received_at) })
      .to eq([ { "provider" => "sendgrid", "provider_event_id" => "ev-1", "received_at" => now } ])
    expect(rows.first.payload).to eq(event.slice(*described_class::STORED_KEYS))
    expect(rows.first.payload.to_json).not_to include("@")
    expect(process_jobs.count).to eq(1)
  end

  it "同じ sg_event_id の 2 回目は捨て、処理のジョブも足さない" do
    event = sendgrid_event(sg_event_id: "ev-1")
    2.times { receive(*signed_sendgrid_events([ event, event ], at: now)) }

    expect(rows.size).to eq(1)
    expect(process_jobs.count).to eq(1)
  end

  it "署名が合わない・別の鍵・時刻を書き換えた・ヘッダが無い要求は書かない" do
    body, signature, timestamp = signed_sendgrid_events([ sendgrid_event ], at: now)
    other_key = OpenSSL::PKey::EC.generate("prime256v1")

    expect(receive(body.sub("delivered", "bounce"), signature, timestamp)).to eq(:unauthorized)
    expect(receive(*signed_sendgrid_events([ sendgrid_event ], at: now, key: other_key))).to eq(:unauthorized)
    expect(receive(body, signature, (timestamp.to_i + 1).to_s)).to eq(:unauthorized)
    expect(receive(body, nil, timestamp)).to eq(:unauthorized)
    expect(receive(body, "not base64!", timestamp)).to eq(:unauthorized)
    expect(rows).to be_empty
    # 同じ本文と署名を書き換えずに送れば受け付ける（対照）
    expect(receive(body, signature, timestamp)).to eq(:ok)
  end

  it "署名の時刻が受け取った時刻から 10 分より離れていれば受け付けない" do
    expect(receive(*signed_sendgrid_events([ sendgrid_event ], at: now - 10.minutes - 1))).to eq(:unauthorized)
    expect(receive(*signed_sendgrid_events([ sendgrid_event ], at: now + 10.minutes + 1))).to eq(:unauthorized)
    expect(receive(*signed_sendgrid_events([ sendgrid_event ], at: now - 10.minutes))).to eq(:ok)
  end

  it "公開鍵を設定していなければ受け付けない" do
    signed = signed_sendgrid_events([ sendgrid_event ], at: now)
    Rails.configuration.x.notifications.sendgrid_webhook_public_key = nil

    expect(receive(*signed)).to eq(:unauthorized)
  end

  it "配列でない本文と JSON でない本文は、署名が合っても書かない" do
    body = "{}"
    timestamp = now.to_i.to_s
    signature = Base64.strict_encode64(sendgrid_key.sign("SHA256", "#{timestamp}#{body}"))
    broken = "[{"
    broken_signature = Base64.strict_encode64(sendgrid_key.sign("SHA256", "#{timestamp}#{broken}"))

    expect(receive(body, signature, timestamp)).to eq(:bad_request)
    expect(receive(broken, broken_signature, timestamp)).to eq(:bad_request)
    expect(rows).to be_empty
  end

  it "書くイベントが 1 つも無ければ、処理のジョブを登録しない" do
    expect(receive(*signed_sendgrid_events([ sendgrid_event(sg_event_id: nil) ], at: now))).to eq(:ok)

    expect([ rows, process_jobs.to_a ]).to eq([ [], [] ])
  end

  it "sg_event_id の無いイベントは書かず、他のイベントは書く" do
    expect(receive(*signed_sendgrid_events([ sendgrid_event(sg_event_id: nil), sendgrid_event(sg_event_id: "ev-2") ], at: now)))
      .to eq(:ok)

    expect(rows.map(&:provider_event_id)).to eq([ "ev-2" ])
  end
end
