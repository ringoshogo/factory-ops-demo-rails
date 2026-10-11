require "rails_helper"
require_relative "../support/sendgrid_webhook"

# SendGrid のイベント Webhook の入口（docs/adr/007 決定 5 の A-3）。セッションを使わず署名で認証し、受信の表に書いてすぐ応答する
RSpec.describe "POST /webhooks/sendgrid/events", type: :request do
  include SendgridWebhookHelpers

  def post_events(body, signature, timestamp)
    post "/webhooks/sendgrid/events", params: body, headers: {
      "CONTENT_TYPE" => "application/json",
      "X-Twilio-Email-Event-Webhook-Signature" => signature,
      "X-Twilio-Email-Event-Webhook-Timestamp" => timestamp
    }
  end

  # 受信の表のモデルはパッケージの外から参照できないので、表を読む
  def rows
    ApplicationRecord.connection.select_all("SELECT provider_event_id, payload FROM webhook_inbox_events").map do |row|
      Data.define(:provider_event_id, :payload).new(provider_event_id: row["provider_event_id"], payload: JSON.parse(row["payload"]))
    end
  end

  it "署名の合うイベントを、ログインなしで受け取って 200 を返し、メールアドレスを残さない" do
    post_events(*signed_sendgrid_events([ sendgrid_event(sg_event_id: "ev-1") ]))

    expect(response).to have_http_status(:ok)
    expect(rows.map(&:provider_event_id)).to eq([ "ev-1" ])
    expect(rows.first.payload.to_json).not_to include("@")
  end

  it "同じ sg_event_id を 2 回受け取っても、行は 1 件" do
    signed = signed_sendgrid_events([ sendgrid_event(sg_event_id: "ev-1") ])
    2.times { post_events(*signed) }

    expect(response).to have_http_status(:ok)
    expect(rows.size).to eq(1)
  end

  it "署名が合わなければ 401 を返し、書かない" do
    body, signature, timestamp = signed_sendgrid_events([ sendgrid_event ])

    post_events(body.sub("delivered", "bounce"), signature, timestamp)

    expect(response).to have_http_status(:unauthorized)
    expect(rows).to be_empty
  end

  it "配列でない本文は 400 を返す" do
    body = "{}"
    timestamp = Time.current.to_i.to_s

    post_events(body, Base64.strict_encode64(sendgrid_key.sign("SHA256", "#{timestamp}#{body}")), timestamp)

    expect(response).to have_http_status(:bad_request)
  end

  it "受け取ったイベントの処理のジョブを流すと、送信記録の時刻列が書かれる" do
    tenant = FactoryBot.create(:tenant).id
    delivery = Tenancy.with_tenant(tenant) { FactoryBot.create(:email_delivery, accepted_at: Time.current) }

    post_events(*signed_sendgrid_events([ sendgrid_event(tenant_id: tenant, email_delivery_id: delivery.id, timestamp: 1_791_000_000) ]))
    job = SolidQueue::Job.find_by!(class_name: "Notifications::ProcessInboxJob", finished_at: nil)
    ActiveJob::Base.execute(job.arguments)

    expect(Tenancy.with_tenant(tenant) { delivery.reload.delivered_at }).to eq(Time.zone.at(1_791_000_000))
  end
end
