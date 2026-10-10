require "rails_helper"
require_relative "../../../../../spec/support/owner_connection"

# 受注を作る照合と対応表の登録が同時に進んでも、照合待ちの受注を見落とさない（Sales::PartMatching.lock）。
# 2 つの接続で同時に動かすので、例ごとのトランザクションを使わず、作った行は例の後で所有ロールで消す
RSpec.describe Sales::PartMappings do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let!(:item) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:partnership, buyer_tenant_id: buyer.id)
      FactoryBot.create(:item)
    end
  end
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:event) do
    Contracts::PurchaseOrderPlaced.new(purchase_order_id: SecureRandom.uuid, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id,
      desired_delivery_on: nil, lines: [ { "purchase_order_line_id" => SecureRandom.uuid, "part_number" => "MY-BOLT", "quantity" => 1 } ])
  end

  after do
    connection = OwnerConnection.lease_connection
    ids = [ supplier.id, buyer.id ].map { connection.quote(_1) }.join(", ")
    %w[sales_order_lines sales_orders sales_order_sequences customer_part_mappings items partnership_grants partnerships].each do |table|
      connection.execute("DELETE FROM #{table} WHERE owner_tenant_id IN (#{ids})")
    end
    connection.execute("DELETE FROM solid_queue_jobs WHERE class_name = 'Contracts::EventJob'")
    connection.execute("DELETE FROM tenants WHERE id IN (#{ids})")
  end

  def statuses
    Tenancy.with_tenant(supplier.id) { Sales::SalesOrders.list(actor, first: 10, after: nil).values.map(&:status) }
  end

  # 相手の接続が、取引先ごとのロックを待っているか
  def waiting_for_lock?
    ActiveRecord::Base.lease_connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND wait_event = 'advisory'"
    ).positive?
  end

  it "ACL が照合待ちの受注をコミットする前に登録しても、登録は ACL のコミットを待って照合し直す" do
    translated = Queue.new
    commit = Queue.new
    translator = Thread.new do
      Tenancy.with_tenant(supplier.id) do
        Sales::PurchaseOrderTranslator.handle(event)
        translated << true
        commit.pop
      end
    end
    translated.pop

    registering = Thread.new do
      Tenancy.with_tenant(supplier.id) do
        described_class.register(actor, customer_tenant_id: buyer.id, customer_part_number: "MY-BOLT", item_id: item.id)
      end
    end
    deadline = 5.seconds.from_now
    sleep 0.01 until !registering.alive? || waiting_for_lock? || Time.current > deadline
    commit << true

    expect(registering.value).to be_success
    translator.join
    expect(statuses).to eq([ :received ])
  end
end
