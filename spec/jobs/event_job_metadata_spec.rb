require "rails_helper"
require_relative "../support/tenant_helpers"
require_relative "../support/events"

# イベントのジョブは付帯情報を必須とする。付帯情報が無ければ、受け手の書き込みを戻して専用の例外で失敗する。
# 受信の監査の行を書けないまま受け手の書き込みだけを残すと、相手テナントに効果が及ぶ書き込みが記録されなくなるからである
# （docs/guides/config.md「ログ」、docs/architecture/graphql-schema.md「監査ログ」）
RSpec.describe Contracts::EventJob do
  include TenantHelpers

  let!(:source) { create_tenant("source") }
  let!(:destination) { create_tenant("destination") }

  before do
    stub_const("Contracts::SpecPinged", Contracts::Event.define(:tenant_id))
    # 宛先テナントにユーザーを 1 人書く受け手
    stub_const("SpecReceiver", Class.new do
      extend TenantHelpers
      def self.handle(event) = insert_user(event.tenant_id, "#{SecureRandom.hex(4)}@example.com")
    end)
    stub_const("Contracts::Subscriptions::TABLE", {
      "Contracts::SpecPinged" => [ Contracts::Subscriptions::Route.new(receiver: "SpecReceiver", tenant_key: "tenant_id") ]
    })
    Tenancy.with_tenant(source) { Contracts.publish(Contracts::SpecPinged.new(tenant_id: destination)) }
  end

  def job_data = enqueued_event_jobs.sole.arguments

  def user_count = Tenancy.with_tenant(destination) { connection.select_value("SELECT count(*) FROM users") }

  def receipt_count = Tenancy.with_tenant(destination) { AuditLog.where(action: "event.received").count }

  it "付帯情報があれば、受け手が書き、受信の監査の行も書く" do
    ActiveJob::Base.execute(job_data)

    expect([ user_count, receipt_count ]).to eq([ 1, 1 ])
  end

  it "付帯情報の無い形で直列化したジョブは、受け手の書き込みを残さずに MissingMetadata で失敗する" do
    expect { ActiveJob::Base.execute(job_data.except("app_metadata")) }.to raise_error(described_class::MissingMetadata)

    expect([ user_count, receipt_count ]).to eq([ 0, 0 ])
  end

  # 実装の一覧から作らない。実装から項目を外すと、その項目を確かめる example も消えるからである
  %w[event_id event_name correlation_id source_tenant_id published_at].each do |key|
    it "付帯情報に #{key} が無ければ、受け手の書き込みを残さずに MissingMetadata で失敗する" do
      data = job_data.merge("app_metadata" => job_data.fetch("app_metadata").except(key))

      expect { ActiveJob::Base.execute(data) }.to raise_error(described_class::MissingMetadata, /#{key}/)
      expect([ user_count, receipt_count ]).to eq([ 0, 0 ])
    end
  end
end
