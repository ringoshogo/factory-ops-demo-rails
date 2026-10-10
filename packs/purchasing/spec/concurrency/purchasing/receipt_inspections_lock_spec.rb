require "rails_helper"
require_relative "../../../../../spec/support/concurrency"
require_relative "../../../../../spec/support/events"

# 同じ入荷への 2 つの検収が並んだときの順序（docs/architecture/context-map.md「検収と請求の流れ」1）。
# 先の検収が入荷の行ロックを持つ間は後の検収が待ち、コミットの後は CONFLICT になって「検収完了」を出さない
RSpec.describe "同じ入荷への検収の競合" do
  self.use_transactional_tests = false

  let!(:buyer) { FactoryBot.create(:tenant, code: "inspection-lock-#{SecureRandom.hex(6)}") }
  let!(:supplier) { FactoryBot.create(:tenant, code: "inspection-lock-#{SecureRandom.hex(6)}") }
  let!(:inbound_line) do
    Tenancy.with_tenant(buyer.id) do
      order = FactoryBot.create(:purchase_order, supplier_tenant_id: supplier.id)
      FactoryBot.create(:inbound_shipment_line, inbound_shipment: FactoryBot.create(:inbound_shipment, purchase_order: order),
        purchase_order_line: FactoryBot.create(:purchase_order_line, purchase_order: order, quantity: 3))
    end
  end

  after do
    delete_owned_rows([ buyer.id, supplier.id ],
      %w[receipt_inspection_lines receipt_inspections inbound_shipment_lines inbound_shipments purchase_order_lines purchase_orders])
  end

  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "") }

  def inspect_receipt(accepted_quantity)
    Purchasing::ReceiptInspections.record(actor, inbound_shipment_id: inbound_line.inbound_shipment_id,
      lines: [ { inbound_shipment_line_id: inbound_line.id, accepted_quantity: } ])
  end

  # 発注側テナントが登録した「検収完了」のジョブ。ほかの実行のジョブを数えない
  def inspected_jobs
    enqueued_event_jobs.map { _1.arguments.fetch("arguments") }
      .select { |name, payload| name == "Contracts::ReceiptInspected" && payload.fetch("buyer_tenant_id") == buyer.id }
  end

  it "先の検収がコミットするまで後の検収は待ち、コミットの後は CONFLICT で、検収と「検収完了」は先の 1 回分だけ残る" do
    first, release, first_thread = hold_open(buyer.id) { inspect_receipt(3) }
    expect(first).to be_success

    second_thread = in_thread(buyer.id) { inspect_receipt(0) }
    expect(blocked_on_lock?(second_thread, by: first_thread)).to be(true)

    expect(commit(release, first_thread)).to be_success
    expect(finish(second_thread).failures.map(&:code)).to eq([ :conflict ])
    expect(Tenancy.with_tenant(buyer.id) { Purchasing::PurchaseOrders.inbound_shipment_lines_for(actor, [ inbound_line.inbound_shipment_id ]) }
      .fetch(inbound_line.inbound_shipment_id).map(&:accepted_quantity)).to eq([ 3 ])
    expect(inspected_jobs.map { _2.fetch("lines").map { |line| line.slice("purchase_order_line_id", "accepted_quantity") } })
      .to eq([ [ { "purchase_order_line_id" => inbound_line.purchase_order_line_id, "accepted_quantity" => 3 } ] ])
  end
end
