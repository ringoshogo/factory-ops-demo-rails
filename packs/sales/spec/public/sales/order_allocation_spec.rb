require "rails_helper"

# 受注の引当（docs/implementation-plan.md M12 の完了条件、docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
RSpec.describe Sales::OrderAllocation do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  around { |example| Tenancy.with_tenant(supplier.id) { example.run } }

  let(:item) { FactoryBot.create(:item) }
  let(:order) do
    FactoryBot.create(:sales_order).tap do |order|
      [ 3, 2 ].each { FactoryBot.create(:sales_order_line, :matched, sales_order: order, item_id: item.id, quantity: _1) }
    end
  end

  def stock_in(quantity) = Inventory::Adjustment.adjust(actor, item_id: item.id, type: "inbound", quantity:)

  def allocate = described_class.allocate(actor, sales_order_id: order.id)

  def allocated_quantities = Sales::SalesOrders.lines_for(actor, [ order.id ]).fetch(order.id).map(&:allocated_quantity)

  it "一部を引き当てると一部引当、全量を引き当てると引当済になり、全量になったときに 1 回だけ出荷可能を出す" do
    ready = []
    allow(Contracts).to receive(:publish).and_wrap_original { |original, event| ready << event.class; original.call(event) }

    stock_in(4)
    expect(allocate.value.status).to eq(:partially_allocated)
    expect(allocated_quantities).to eq([ 3, 1 ])

    stock_in(1)
    expect(allocate.value.status).to eq(:allocated)
    expect(allocate.value.status).to eq(:allocated)
    expect(allocated_quantities).to eq([ 3, 2 ])
    expect(ready).to eq([ Contracts::SalesOrderReadyForShipment ])
  end

  it "出荷可能は、出荷が出荷計上で返す発注明細 ID と、宛先を決める受注側テナントを運ぶ" do
    stock_in(5)
    expect(Contracts).to receive(:publish) do |event|
      expect(event.to_payload).to include("sales_order_id" => order.id, "supplier_tenant_id" => supplier.id,
        "buyer_tenant_id" => order.customer_tenant_id, "purchase_order_id" => order.source_purchase_order_id)
      expect(event.lines.map { _1["purchase_order_line_id"] }).to eq(order.lines.map(&:source_purchase_order_line_id))
    end

    allocate
  end

  it "有効在庫が無ければ何も引き当てず、受注済のまま" do
    expect(allocate.value.status).to eq(:received)
    expect(allocated_quantities).to eq([ 0, 0 ])
  end

  it "品番照合待ちの受注と、見えない受注は引き当てない" do
    FactoryBot.create(:sales_order_line, sales_order: order)

    expect(allocate.failures.map(&:code)).to eq([ :conflict ])
    expect(described_class.allocate(actor, sales_order_id: SecureRandom.uuid).failures.map(&:code)).to eq([ :not_found ])
  end

  it "ロックを受注 → 受注明細（id 順）→ 在庫（item_id 昇順）→ 引当（受注明細 ID 順）の順に取る" do
    other_item = FactoryBot.create(:item)
    FactoryBot.create(:sales_order_line, :matched, sales_order: order, item_id: other_item.id)
    stock_in(5)
    order

    locks = []
    callback = lambda do |*, payload|
      locks << payload[:sql][/FROM "(\w+)"/, 1] + payload[:sql][/ORDER BY (.*) FOR UPDATE/, 1].to_s if payload[:sql].include?("FOR UPDATE")
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { allocate }

    expect(locks).to eq([
      "sales_orders",
      %(sales_order_lines"sales_order_lines"."id" ASC),
      %(stocks"stocks"."item_id" ASC),
      %(allocations"allocations"."sales_order_line_id" ASC)
    ])
  end
end
