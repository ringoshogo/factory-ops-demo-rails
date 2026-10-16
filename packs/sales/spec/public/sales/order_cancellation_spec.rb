require "rails_helper"

# 受注側の取消。審査を経ずに、引当の解除と受注の取消を同じトランザクションで行い、「受注取消」と「出荷取消」を出す。
# 出荷済・取消済の受注、未決の取消の審査がある受注、引当が消費済みの受注は CONFLICT で、失敗は書き込みもイベントも残さない
# （docs/architecture/context-map.md「取消の流れ」、docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
RSpec.describe Sales::OrderCancellation do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:buyer) { FactoryBot.create(:tenant) }

  around { |example| TenantExample.run(example, supplier.id) }

  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:item) { FactoryBot.create(:item) }
  let!(:order) do
    FactoryBot.create(:sales_order, customer_tenant_id: buyer.id).tap do |order|
      [ 3, 2 ].each { FactoryBot.create(:sales_order_line, :matched, sales_order: order, item_id: item.id, quantity: _1) }
    end
  end

  let(:published) { [] }

  before { allow(Contracts).to receive(:publish).and_wrap_original { |original, event| published << event; original.call(event) } }

  def allocate(quantity)
    Inventory::Adjustment.adjust(actor, item_id: item.id, type: "inbound", quantity:)
    Sales::OrderAllocation.allocate(actor, sales_order_id: order.id)
    published.clear
  end

  def cancel(id = order.id) = described_class.cancel(actor, sales_order_id: id)

  def allocated_quantities = Sales::SalesOrders.lines_for(actor, [ order.id ]).fetch(order.id).map(&:allocated_quantity)

  def stock = Inventory::Stocks.for_items(actor, [ item.id ]).fetch(item.id)

  def failure_codes(result) = result.failures.map(&:code)

  it "引当を解除して受注を取消済にし、「受注取消」と「出荷取消」を出す" do
    allocate(5)

    result = cancel

    expect(result.value).to have_attributes(id: order.id, status: :cancelled)
    expect(order.reload.cancelled_at).to be_present
    expect(allocated_quantities).to eq([ 0, 0 ])
    expect(stock).to have_attributes(on_hand: 5, allocated: 0)
    expect(published.map(&:class)).to contain_exactly(Contracts::SalesOrderCancelled, Contracts::ShipmentCancelled)
    expect(published.find { _1.is_a?(Contracts::SalesOrderCancelled) }).to have_attributes(
      purchase_order_id: order.source_purchase_order_id, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id)
    expect(published.find { _1.is_a?(Contracts::ShipmentCancelled) }).to have_attributes(sales_order_id: order.id,
      supplier_tenant_id: supplier.id, cancellation_review_id: nil, ready_for_shipment: true)
  end

  it "全量を引き当てていない受注の「出荷取消」は、出荷可能を出していないことを運ぶ" do
    allocate(4)

    expect(cancel).to be_success
    expect(published.find { _1.is_a?(Contracts::ShipmentCancelled) }.ready_for_shipment).to be(false)
    expect(stock).to have_attributes(on_hand: 4, allocated: 0)
  end

  it "品番照合待ちの受注は、引当が無いまま取り消せ、出荷可能を出していないことを運ぶ" do
    awaiting = FactoryBot.create(:sales_order, customer_tenant_id: buyer.id)
    FactoryBot.create(:sales_order_line, sales_order: awaiting)

    expect(cancel(awaiting.id).value).to have_attributes(id: awaiting.id, status: :cancelled)
    expect(published.map(&:class)).to contain_exactly(Contracts::SalesOrderCancelled, Contracts::ShipmentCancelled)
    expect(published.find { _1.is_a?(Contracts::ShipmentCancelled) })
      .to have_attributes(sales_order_id: awaiting.id, cancellation_review_id: nil, ready_for_shipment: false)
  end

  it "決着した審査だけがある受注は取り消せる" do
    FactoryBot.create(:cancellation_review, sales_order: order, decision: "rejected", decided_at: 1.day.ago)

    expect(cancel).to be_success
    expect(order.reload.cancelled_at).to be_present
  end

  describe "失敗" do
    before { allocate(5) }

    def expect_unchanged
      expect(order.reload.cancelled_at).to be_nil
      expect(allocated_quantities).to eq([ 3, 2 ])
      expect(published).to be_empty
    end

    { "出荷済" => :shipped_at, "取消済" => :cancelled_at }.each do |name, column|
      it "#{name}の受注は CONFLICT で、引当を変えずイベントを出さない" do
        order.update!(column => 1.day.ago)

        expect(failure_codes(cancel)).to eq([ :conflict ])
        expect(order.reload.public_send(column)).to be_within(1.second).of(1.day.ago)
        expect(allocated_quantities).to eq([ 3, 2 ])
        expect(published).to be_empty
      end
    end

    it "未決の取消の審査がある受注は CONFLICT で、引当と審査を変えずイベントを出さない" do
      review = FactoryBot.create(:cancellation_review, sales_order: order)

      expect(failure_codes(cancel)).to eq([ :conflict ])
      expect(review.reload.decision).to be_nil
      expect_unchanged
    end

    it "引当が消費済み（出荷の計上が先に成立した）なら CONFLICT で、受注と在庫を変えずイベントを出さない" do
      Inventory::Allocation.consume(actor, order.lines.map(&:id))

      expect(failure_codes(cancel)).to eq([ :conflict ])
      expect(order.reload.cancelled_at).to be_nil
      expect(stock).to have_attributes(on_hand: 0, allocated: 0)
      expect(published).to be_empty
    end

    # 他社の受注の ID は、入口の行列（spec/matrix）と S1 が確かめる
    it "無い受注は NOT_FOUND" do
      expect(cancel(SecureRandom.uuid).failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :sales_order_id ] ] ])
      expect_unchanged
    end
  end
end
