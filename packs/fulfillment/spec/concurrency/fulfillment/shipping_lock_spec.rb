require "rails_helper"
require_relative "../../../../../spec/support/concurrency"

# 同じ出荷依頼への計上どうしと、計上と出荷指示の取消を 2 つの接続で同時に動かしても、どちらか一方だけが成立する。
# 出荷停止の受け手も同じ行ロックを取るので、停止は計上の途中に割り込まない。出荷依頼の行ロックが同じ出荷依頼への操作を直列にする
# （docs/architecture/data-model.md「取消と出荷の競合を止める場所」「出荷（`fulfillment`）」）
RSpec.describe Fulfillment::Shipping do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:item_id) { SecureRandom.uuid }
  # 在庫を 10 入れ、出荷依頼の明細 2 つ（3 と 2）を全量で引き当て、有効な出荷指示を作っておく
  let!(:request) do
    Tenancy.with_tenant(supplier.id) do
      Inventory::Adjustment.adjust(actor, item_id:, type: "inbound", quantity: 10)
      FactoryBot.create(:shipping_instruction).shipment_request.tap do |request|
        [ 3, 2 ].each do |quantity|
          line = FactoryBot.create(:shipment_request_line, shipment_request: request, item_id:, quantity:)
          Inventory::Allocation.allocate(actor, [ { sales_order_line_id: line.sales_order_line_id, item_id:, quantity: } ])
        end
      end
    end
  end

  after do
    delete_owned_rows([ supplier.id, request.buyer_tenant_id ], %w[
      shipment_lines shipments shipping_instructions shipping_holds shipment_request_lines shipment_requests
      stock_movements allocations stocks
    ])
  end

  def post = described_class.post(actor, shipment_request_id: request.id, shipped_on: Date.new(2026, 10, 9))
  def cancel = Fulfillment::Instructions.cancel(actor, shipment_request_id: request.id)

  def shipped
    Tenancy.with_tenant(supplier.id) do
      [ Fulfillment::Shipment.where(shipment_request_id: request.id).count,
        Inventory::Stocks.for_items(actor, [ item_id ]).fetch(item_id).to_h.slice(:on_hand, :allocated) ]
    end
  end

  def instruction_statuses = Tenancy.with_tenant(supplier.id) { request.instructions.pluck(:status) }

  it "同じ出荷依頼の計上が同時に来ると、後の計上は先の計上のコミットを待ち、CONFLICT になる。出荷実績は 1 件だけできる" do
    posted, release, poster = hold_open(supplier.id) { post }
    expect(posted).to be_success

    second = in_thread(supplier.id) { post }
    expect(blocked_on_lock?(second, by: poster)).to be(true)

    expect(commit(release, poster)).to be_success
    expect(finish(second).failures.map(&:code)).to eq([ :conflict ])
    expect(shipped).to eq([ 1, { on_hand: 5, allocated: 0 } ])
  end

  it "計上がコミットするまで出荷指示の取消は待ち、コミットの後は CONFLICT になる" do
    posted, release, poster = hold_open(supplier.id) { post }
    expect(posted).to be_success

    canceller = in_thread(supplier.id) { cancel }
    expect(blocked_on_lock?(canceller, by: poster)).to be(true)

    expect(commit(release, poster)).to be_success
    expect(finish(canceller).failures.map(&:code)).to eq([ :conflict ])
    expect(instruction_statuses).to eq([ "active" ])
    expect(shipped).to eq([ 1, { on_hand: 5, allocated: 0 } ])
  end

  it "出荷指示の取消がコミットするまで計上は待ち、コミットの後は CONFLICT になる" do
    cancelled, release, canceller = hold_open(supplier.id) { cancel }
    expect(cancelled).to be_success

    poster = in_thread(supplier.id) { post }
    expect(blocked_on_lock?(poster, by: canceller)).to be(true)

    expect(commit(release, canceller)).to be_success
    expect(finish(poster).failures.map(&:code)).to eq([ :conflict ])
    expect(instruction_statuses).to eq([ "cancelled" ])
    expect(shipped).to eq([ 0, { on_hand: 10, allocated: 5 } ])
  end

  it "出荷停止の受け手がコミットするまで計上は待ち、コミットの後は CONFLICT になる" do
    held = Contracts::ShippingHeld.new(cancellation_review_id: SecureRandom.uuid, sales_order_id: request.sales_order_id,
      supplier_tenant_id: supplier.id)
    _, release, holder = hold_open(supplier.id) { Fulfillment::SalesEventReceiver.handle(held) }

    poster = in_thread(supplier.id) { post }
    expect(blocked_on_lock?(poster, by: holder)).to be(true)

    commit(release, holder)
    expect(finish(poster).failures.map(&:code)).to eq([ :conflict ])
    expect(shipped).to eq([ 0, { on_hand: 10, allocated: 5 } ])
  end
end
