require "rails_helper"
require_relative "../support/tenant_helpers"
require_relative "../support/events"
require_relative "../support/shared_examples/idempotent_receiver"

# Contracts.publish から受け手までの流れ。業務のイベントはまだ無いので、テスト用のイベントと受け手を配送表に載せる
RSpec.describe Contracts do
  include TenantHelpers

  let!(:buyer) { create_tenant("buyer") }
  let!(:supplier) { create_tenant("supplier") }

  # 宛先テナントにユーザーを 1 人作る受け手。メールアドレスの一意制約を冪等キーにする
  let(:receiver) do
    Class.new do
      def self.handle(event)
        ActiveRecord::Base.lease_connection.exec_query(<<~SQL, "SpecReceiver", [ Current.tenant_id, event.email ])
          INSERT INTO users (owner_tenant_id, email, name, role, password_digest, created_at, updated_at)
          VALUES ($1, $2, 'name', 'member', 'x', now(), now())
          ON CONFLICT (email) DO NOTHING
        SQL
      end
    end
  end

  before do
    stub_const("Contracts::SpecPinged", Contracts::Event.define(:ping_id, :buyer_tenant_id, :supplier_tenant_id, :email))
    stub_const("SpecBuyerReceiver", Class.new { def self.handle(_event) = nil })
    stub_const("SpecSupplierReceiver", receiver)
    stub_const("Contracts::Subscriptions::TABLE", {
      "Contracts::SpecPinged" => [
        Contracts::Subscriptions::Route.new(receiver: "SpecBuyerReceiver", tenant_key: "buyer_tenant_id"),
        Contracts::Subscriptions::Route.new(receiver: "SpecSupplierReceiver", tenant_key: "supplier_tenant_id")
      ]
    })
  end

  let(:event) { Contracts::SpecPinged.new(ping_id: "p1", buyer_tenant_id: buyer, supplier_tenant_id: supplier, email: "ping@example.com") }

  def users_of(tenant)
    Tenancy.with_tenant(tenant) { connection.select_values("SELECT email FROM users") }
  end

  it "受け手ごとにジョブを 1 件ずつ登録する" do
    Tenancy.with_tenant(buyer) { described_class.publish(event) }

    expect(enqueued_event_jobs.map { |job| job.arguments["arguments"].values_at(2, 3) })
      .to eq([ [ "SpecBuyerReceiver", buyer ], [ "SpecSupplierReceiver", supplier ] ])
  end

  it "受け手は、発行元ではなく宛先テナントの名義で書く" do
    seen = []
    allow(SpecSupplierReceiver).to receive(:handle).and_wrap_original do |original, received|
      seen << [ Current.tenant_id, received ]
      original.call(received)
    end

    Tenancy.with_tenant(buyer) { described_class.publish(event) }
    deliver_enqueued_events

    expect(seen).to eq([ [ supplier, event ] ])
    expect(users_of(supplier)).to eq([ "ping@example.com" ])
  end

  it "トランザクションの外で呼ぶと例外になる" do
    expect { described_class.publish(event) }.to raise_error(Contracts::OutsideTransaction)
  end

  it "配送表に無いイベントは登録できない" do
    stub_const("Contracts::SpecUnrouted", Contracts::Event.define(:id))

    expect { Tenancy.with_tenant(buyer) { described_class.publish(Contracts::SpecUnrouted.new(id: "x")) } }
      .to raise_error(KeyError)
  end

  it "プリミティブでない値を運ぶイベントは登録できない" do
    event = Contracts::SpecPinged.new(ping_id: "p1", buyer_tenant_id: buyer, supplier_tenant_id: supplier, email: Time.current)

    expect { Tenancy.with_tenant(buyer) { described_class.publish(event) } }.to raise_error(ArgumentError, /プリミティブ/)
    expect(enqueued_event_jobs).to be_empty
  end

  it "配送表に無い受け手を指すジョブは実行しない" do
    job = Contracts::EventJob.new("Contracts::SpecPinged", event.to_payload, "Kernel", supplier) # rubocop:disable FactoryOps/EventJobEnqueue

    expect { job.perform_now }.to raise_error(KeyError, /配送表に無い受け手/)
  end

  # 引数の宛先テナントを信じると、ペイロードと別のテナントの名義で受け手が書く
  it "引数の宛先テナントが、配送表の項目が指すペイロードの値と違うジョブは実行しない" do
    job = Contracts::EventJob.new("Contracts::SpecPinged", event.to_payload, "SpecSupplierReceiver", buyer) # rubocop:disable FactoryOps/EventJobEnqueue
    expect(SpecSupplierReceiver).not_to receive(:handle)

    expect { job.perform_now }.to raise_error(Contracts::EventJob::TenantMismatch)
  end

  describe "Contracts.publish を通らない登録" do
    let(:arguments) { [ "Contracts::SpecPinged", event.to_payload, "SpecSupplierReceiver", supplier ] }

    def expect_rejected(&enqueue)
      expect { Tenancy.with_tenant(buyer, &enqueue) }.to raise_error(Contracts::EventJob::OutsidePublish)
      expect(enqueued_event_jobs).to be_empty
    end

    # rubocop:disable FactoryOps/EventJobEnqueue
    it "perform_later を拒む" do
      expect_rejected { Contracts::EventJob.perform_later(*arguments) }
    end

    it "set を挟んだ perform_later を拒む" do
      expect_rejected { Contracts::EventJob.set(wait: 1).perform_later(*arguments) }
    end

    it "ジョブを作ってからの enqueue を拒む" do
      expect_rejected { Contracts::EventJob.new(*arguments).enqueue }
    end

    it "enqueue のコールバックを通らない ActiveJob.perform_all_later を拒む" do
      expect_rejected { ActiveJob.perform_all_later(Contracts::EventJob.new(*arguments)) }
    end
    # rubocop:enable FactoryOps/EventJobEnqueue

    it "サブクラスを作れない" do
      expect { Class.new(Contracts::EventJob) }.to raise_error(TypeError)
    end

    it "Contracts.publish を抜けた後の登録も拒む" do
      Tenancy.with_tenant(buyer) { described_class.publish(event) }

      expect { Tenancy.with_tenant(buyer) { Contracts::EventJob.perform_later(*arguments) } } # rubocop:disable FactoryOps/EventJobEnqueue
        .to raise_error(Contracts::EventJob::OutsidePublish)
    end
  end

  it_behaves_like "冪等な受け手" do
    let(:publish_event) { -> { Tenancy.with_tenant(buyer) { described_class.publish(event) } } }
    let(:written_rows) { -> { users_of(supplier).size } }
  end
end
