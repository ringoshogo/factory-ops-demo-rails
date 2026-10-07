require "rails_helper"
require_relative "../../../../../spec/support/owner_connection"

# 同じ品目を 2 つの受注が同時に引き当てても、有効在庫を超えて引き当てない（docs/architecture/data-model.md「在庫」）。
# 2 つの接続で同時に動かすので、例ごとのトランザクションを使わず、作った行は例の後で所有ロールで消す
RSpec.describe Sales::OrderAllocation do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item) } }
  let!(:orders) do
    Tenancy.with_tenant(supplier.id) do
      Inventory::Adjustment.adjust(actor, item_id: item.id, type: "inbound", quantity: 10)
      Array.new(2) do
        FactoryBot.create(:sales_order).tap { FactoryBot.create(:sales_order_line, :matched, sales_order: _1, item_id: item.id, quantity: 10) }
      end
    end
  end

  after do
    @threads&.each { _1.join(10) }
    connection = OwnerConnection.lease_connection
    tenants = [ supplier.id, *orders.map(&:customer_tenant_id) ].map { connection.quote(_1) }.join(", ")
    %w[stock_movements allocations stocks sales_order_lines sales_orders items].each do |table|
      connection.execute("DELETE FROM #{table} WHERE owner_tenant_id IN (#{tenants})")
    end
    connection.execute("DELETE FROM tenants WHERE id IN (#{tenants})")
  end

  def in_thread(&block)
    Thread.new { Tenancy.with_tenant(supplier.id, &block) }.tap do |thread|
      thread.report_on_exception = false
      (@threads ||= []) << thread
    end
  end

  def waiting_for_lock?
    ActiveRecord::Base.lease_connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'"
    ).positive?
  end

  it "先の引当がコミットするまで後の引当は在庫の行で待ち、後の引当は残りの有効在庫だけを引き当てる" do
    allocated = Queue.new
    commit = Queue.new
    first = in_thread do
      described_class.allocate(actor, sales_order_id: orders[0].id).tap do
        allocated << true
        commit.pop
      end
    end
    allocated.pop

    second = in_thread { described_class.allocate(actor, sales_order_id: orders[1].id) }
    deadline = 5.seconds.from_now
    sleep 0.01 until !second.alive? || waiting_for_lock? || Time.current > deadline
    expect(waiting_for_lock?).to be(true)
    commit << true

    expect([ first.value.value.status, second.value.value.status ]).to eq(%i[allocated received])
    Tenancy.with_tenant(supplier.id) do
      expect(Inventory::Stocks.for_items(actor, [ item.id ]).fetch(item.id).to_h.slice(:on_hand, :allocated))
        .to eq(on_hand: 10, allocated: 10)
      line_ids = Sales::SalesOrders.lines_for(actor, orders.map(&:id)).values.flatten.map(&:id)
      expect(Inventory::Allocation.quantities_for(actor, line_ids).values.sum).to eq(10)
    end
  end
end
