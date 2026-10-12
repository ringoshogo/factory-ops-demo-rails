require "rails_helper"
require_relative "../support/sendgrid_webhook"

# メンテナンスの切り替え（docs/runbooks/rls-misconfiguration.md「止血」、docs/guides/config.md「メンテナンスの切り替え」）。
# 環境変数 MAINTENANCE_MODE を立てると、GraphQL とファイルの受け口は実行せずに 503 を返す。ログインと SendGrid の Webhook は
# 止めない。Webhook は受信の表に書くだけで、止めると配信結果を失うからである
RSpec.describe "メンテナンスの切り替え", type: :request do
  include SendgridWebhookHelpers

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:admin) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) } }

  around do |example|
    previous = ENV.fetch("MAINTENANCE_MODE", nil)
    ENV["MAINTENANCE_MODE"] = maintenance_mode
    example.run
  ensure
    ENV["MAINTENANCE_MODE"] = previous
  end

  def count(table) = Tenancy.with_tenant(supplier.id) { ApplicationRecord.connection.select_value("SELECT count(*) FROM #{table}") }

  def save_item
    post "/graphql", as: :json, params: {
      query: "mutation($input: SaveItemInput!) { saveItem(input: $input) { item { code } errors { code } } }",
      variables: { input: { code: "M-1", name: "保守", unit: "個", unitPrice: 100 } }
    }
  end

  def upload
    post "/imports/files", headers: { "Origin" => Rails.configuration.x.frontend_origin },
      params: { file: Rack::Test::UploadedFile.new(StringIO.new("item_code,quantity\n"), "text/csv", original_filename: "stocks.csv") }
  end

  def receive_webhook
    body, signature, timestamp = signed_sendgrid_events([ sendgrid_event(sg_event_id: "ev-maintenance") ])
    post "/webhooks/sendgrid/events", params: body, headers: {
      "CONTENT_TYPE" => "application/json",
      "X-Twilio-Email-Event-Webhook-Signature" => signature, "X-Twilio-Email-Event-Webhook-Timestamp" => timestamp
    }
  end

  def inbox_count = ApplicationRecord.connection.select_value("SELECT count(*) FROM webhook_inbox_events")

  context "MAINTENANCE_MODE が立っているとき" do
    let(:maintenance_mode) { "1" }

    it "ログインは通り、GraphQL とファイルの受け口は 503 を返して何も書かない" do
      login_as(admin)

      save_item
      expect(response).to have_http_status(:service_unavailable)
      upload
      expect(response).to have_http_status(:service_unavailable)
      expect([ count("items"), count("import_files") ]).to eq([ 0, 0 ])
    end

    # 本文の形の検査（415）とセッションの確かめ（401）より先に止める
    it "ログインしていない要求と application/json でない要求にも、同じ 503 を返す" do
      post "/graphql", params: "{}", headers: { "CONTENT_TYPE" => "text/plain" }

      expect(response).to have_http_status(:service_unavailable)
    end

    it "SendGrid の Webhook は受け取って、受信の表に書く" do
      receive_webhook

      expect(response).to have_http_status(:ok)
      expect(inbox_count).to eq(1)
    end
  end

  # 立てないときに同じ要求が通ることで、上の 503 が要求の誤りでないことを確かめる
  context "MAINTENANCE_MODE が無いとき" do
    let(:maintenance_mode) { nil }

    it "同じ要求で、GraphQL とファイルの受け口が書く" do
      login_as(admin)

      save_item
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "saveItem", "errors")).to eq([])
      upload
      expect(response).to have_http_status(:created)
      expect([ count("items"), count("import_files") ]).to eq([ 1, 1 ])
    end
  end

  # 値は Rails の真偽値の読み方に従う。0・false・off は立てない側に、それ以外の値は立てる側に読む
  context "MAINTENANCE_MODE が false のとき" do
    let(:maintenance_mode) { "false" }

    it "GraphQL を止めない" do
      login_as(admin)

      save_item
      expect(response).to have_http_status(:ok)
    end
  end
end
