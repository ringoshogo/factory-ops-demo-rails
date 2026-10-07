require "rails_helper"
require_relative "../support/tenant_helpers"
require_relative "../support/events"

# イベントのジョブが業務データと同じトランザクションで登録されることのガードテスト（docs/adr/005 決定 4）
RSpec.describe Contracts::EventJob do
  include TenantHelpers

  let!(:tenant) { create_tenant("a") }

  before do
    stub_const("Contracts::SpecPinged", Contracts::Event.define(:tenant_id))
    stub_const("SpecReceiver", Class.new { def self.handle(_event) = nil })
    stub_const("Contracts::Subscriptions::TABLE", {
      "Contracts::SpecPinged" => [ Contracts::Subscriptions::Route.new(receiver: "SpecReceiver", tenant_key: "tenant_id") ]
    })
  end

  def publish_and_insert_user
    Tenancy.with_tenant(tenant) do
      insert_user(tenant, "a@example.com")
      Contracts.publish(Contracts::SpecPinged.new(tenant_id: tenant))
      yield if block_given?
    end
  end

  def job_count
    connection.select_value("SELECT count(*) FROM solid_queue_jobs")
  end

  it "トランザクションの中で、キューと業務データが同じ接続を使う" do
    ActiveRecord::Base.transaction do
      expect(SolidQueue::Record.lease_connection).to equal(ActiveRecord::Base.lease_connection)
    end
  end

  it "EventJob とそのすべてのサブクラスが、コミットを待たずに登録する" do
    Rails.application.eager_load!

    expect([ described_class, *described_class.descendants ].map(&:enqueue_after_transaction_commit)).to all(be(false))
  end

  it "テストでもアダプタが Solid Queue である" do
    expect(described_class.queue_adapter).to be_a(ActiveJob::QueueAdapters::SolidQueueAdapter)
  end

  it "業務のトランザクションを戻すと、ジョブの行も残らない" do
    in_transaction = nil
    publish_and_insert_user do
      in_transaction = job_count
      raise ActiveRecord::Rollback
    end

    # コミットの後に回さず、業務データと同じトランザクションの中で行を書いている
    expect(in_transaction).to eq(1)
    expect(job_count).to eq(0)
    expect(Tenancy.with_tenant(tenant) { connection.select_value("SELECT count(*) FROM users") }).to eq(0)
  end

  it "業務のトランザクションが確定すると、ジョブの行も残る" do
    publish_and_insert_user

    expect(job_count).to eq(1)
    expect(Tenancy.with_tenant(tenant) { connection.select_value("SELECT count(*) FROM users") }).to eq(1)
  end
end
