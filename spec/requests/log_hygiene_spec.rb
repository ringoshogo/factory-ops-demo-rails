require "rails_helper"
require_relative "../support/events"

# ログに個人情報・秘密・自由記述・GraphQL のクエリの本文と変数の値・ジョブの引数・例外のメッセージを書かない
# （docs/guides/config.md「ログ」）。テストの環境は本番と同じ Platform::Logging.configure! を通るので、
# 本番と同じミドルウェアと購読で要求とジョブを流し、Rails.logger と Rails.event の 2 つの出口の全行を確かめる
RSpec.describe "ログの衛生", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:member) do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, email: "leak-user@example.com", password: "Leak-Pw-1234") }
  end
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item) } }

  # どの行にも現れてはならない値
  let(:forbidden) do
    [ "leak-user@example.com", "Leak-Pw-1234", "LEAK-REASON", "leakQueryMarker", "LEAK-VARIABLE",
      "LEAK-URL-QUERY", "LEAK-URL-VARIABLE", "LEAK-EXCEPTION", "LEAK-JOB-EXCEPTION", "leak-event@example.com" ]
  end

  let(:string_io) { StringIO.new }
  let(:event_io) { StringIO.new }
  # 本番の既定と同じ info の水準で、Rails.logger の行を集める
  let(:string_log) { Platform::Logging.build(string_io).tap { _1.level = :info } }
  let(:event_log) { Platform::JsonLogSubscriber.new(event_io) }

  before do
    stub_const("Contracts::SpecLeaked", Contracts::Event.define(:tenant_id, :email))
    stub_const("SpecLeakReceiver", Class.new { def self.handle(_event) = nil })
    stub_const("Contracts::Subscriptions::TABLE", {
      "Contracts::SpecLeaked" => [ Contracts::Subscriptions::Route.new(receiver: "SpecLeakReceiver", tenant_key: "tenant_id") ]
    })
    stub_const("SpecLeakJob", Class.new(ApplicationJob) { def perform(_secret) = raise("LEAK-JOB-EXCEPTION") })
    Rails.logger.broadcast_to(string_log)
    Rails.event.subscribe(event_log)
  end

  after do
    Rails.logger.stop_broadcasting_to(string_log)
    Rails.event.unsubscribe(event_log)
  end

  def adjust_stock
    post "/graphql", as: :json, params: {
      query: <<~GRAPHQL,
        mutation Adjust($input: AdjustStockInput!) { leakQueryMarker: adjustStock(input: $input) { errors { code } } }
      GRAPHQL
      operationName: "Adjust",
      variables: { input: { itemId: item.id, type: "INBOUND", quantity: 1, reason: "LEAK-REASON leak-user@example.com" },
        email: "leak-user@example.com", password: "Leak-Pw-1234", note: "LEAK-VARIABLE" }
    }
  end

  def lines = [ string_io, event_io ].flat_map { _1.string.lines }

  it "ログイン・mutation・URL の変数・失敗する要求とジョブ・イベントの配送の全行が JSON で、禁止の値を含まない" do
    post "/session", params: { email: "leak-user@example.com", password: "Leak-Pw-1234" }, as: :json
    expect(response).to have_http_status(:no_content)

    adjust_stock
    expect(response.parsed_body.dig("data", "leakQueryMarker", "errors")).to eq([])

    post "/graphql?#{{ query: "{ viewer { id } } # LEAK-URL-QUERY", variables: "LEAK-URL-VARIABLE" }.to_query}", as: :json
    expect(response.parsed_body.dig("data", "viewer", "id")).to eq(member.id)

    # 本番はすべての例外を応答に変えるが、テストの環境が応答に変えるのは rescue できる例外だけなので、それで失敗させる
    allow(Inventory::Adjustment).to receive(:adjust).and_raise(ActiveRecord::RecordNotFound, "LEAK-EXCEPTION")
    adjust_stock
    expect(response).to have_http_status(:not_found)

    job = SpecLeakJob.new("leak-user@example.com")
    error = begin
      Rails.application.executor.wrap { ActiveJob::Base.execute(job.serialize) }
    rescue => e
      e
    end
    expect(error.message).to eq("LEAK-JOB-EXCEPTION")
    # Solid Queue のワーカーは、ジョブの例外をスレッドの外へ上げ、この通知を出す
    SolidQueue.instrument(:thread_error, error:)

    Tenancy.with_tenant(supplier.id) { Contracts.publish(Contracts::SpecLeaked.new(tenant_id: supplier.id, email: "leak-event@example.com")) }
    deliver_enqueued_events

    # 文字列のログの出口が働いていることを、この行で確かめる
    Rails.logger.info("ログの衛生の確認")

    expect(lines.map { JSON.parse(_1) }).to include(include("message" => "ログの衛生の確認"))
    expect(lines.map { JSON.parse(_1)["name"] }).to include("action_controller.request_started", "graphql.operation_completed",
      "action_controller.request_completed", "active_job.completed", "active_job.enqueued", "contracts.event_handled")
    lines.each do |line|
      expect(forbidden.select { line.include?(_1) }).to be_empty, "禁止の値を含む行: #{line}"
    end
  end
end
