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

  it "トランザクションの中で登録するクラスは、イベントのジョブと確実な外部送信のジョブの 2 つだけである（docs/adr/007 決定 3-1）" do
    Rails.application.eager_load!

    in_transaction = ApplicationJob.descendants.select { _1.name&.safe_constantize == _1 }
      .reject(&:enqueue_after_transaction_commit).map(&:name)

    expect(in_transaction).to contain_exactly("Contracts::EventJob", "Notifications::CriticalDeliveryJob")
  end

  it "外部へ作用するジョブは、登録の時機と保証を自分のクラスで宣言し、Cop の登録口の制限の対象に並ぶ（docs/adr/007 決定 4）" do
    Rails.application.eager_load!
    cop_jobs = YAML.load_file(Rails.root.join(".rubocop.yml")).dig("FactoryOps/ExternalEffectEnqueue", "Jobs")
    # 下の example が定義して消したクラスは、GC されるまで descendants に残るので、名前で引き直せるクラスだけを見る
    jobs = ExternalEffectJob.descendants.select { _1.name&.safe_constantize == _1 }

    expect(jobs.map(&:name)).to match_array(cop_jobs)
    expect(jobs.to_h { [ _1.name, [ _1.declares_external_effect?, _1.external_effect_guarantee ] ] })
      .to eq("Notifications::CriticalDeliveryJob" => [ true, :at_least_once ], "Notifications::BestEffortMailJob" => [ true, :best_effort ])
  end

  it "外部へ作用するジョブが登録の時機か保証を書き忘れると、クラスの読み込みで例外になる" do
    declared = <<~RUBY
      class ExternalEffectSpecDeclared < ExternalEffectJob
        self.enqueue_after_transaction_commit = true
        external_effect :best_effort
      end
    RUBY
    expect { Object.class_eval(declared) }.not_to raise_error

    [ "external_effect :best_effort", "self.enqueue_after_transaction_commit = true" ].each_with_index do |line, index|
      name = "ExternalEffectSpecMissing#{index}"
      expect { Object.class_eval("class #{name} < ExternalEffectJob\n  #{line}\nend") }
        .to raise_error(ExternalEffectJob::MissingDeclaration, /#{name}/)
    end
  ensure
    %w[ExternalEffectSpecDeclared ExternalEffectSpecMissing0 ExternalEffectSpecMissing1].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
    end
  end

  it "外部へ作用するジョブの保証は、確実な外部送信か撃ちっぱなしのどちらかで、Class.new の無名のクラスは確かめない" do
    expect { Class.new(ExternalEffectJob) { external_effect :exactly_once } }.to raise_error(ArgumentError, /at_least_once・best_effort/)
    expect { Class.new(ExternalEffectJob) }.not_to raise_error
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
