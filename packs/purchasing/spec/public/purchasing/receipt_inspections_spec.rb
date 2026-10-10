require "rails_helper"
require_relative "../../../../../spec/support/events"

# 入荷検収。入荷の全明細を 1 回で出し、検収数量は 0 以上・出荷数量以下にする。誤りはどれも INVALID_INPUT で、
# 同じ入荷への 2 回目は CONFLICT。失敗は、検収も「検収完了」も残さない（docs/architecture/context-map.md「検収と請求の流れ」1）
RSpec.describe Purchasing::ReceiptInspections, ".record" do
  include ActiveSupport::Testing::TimeHelpers

  let!(:buyer) { FactoryBot.create(:tenant) }
  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:order) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:purchase_order, supplier_tenant_id: supplier.id) } }
  let!(:inbound) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:inbound_shipment, purchase_order: order) } }
  # 出荷数量が 4 と 2 の 2 明細
  let!(:inbound_lines) do
    Tenancy.with_tenant(buyer.id) do
      [ 4, 2 ].map do |quantity|
        FactoryBot.create(:inbound_shipment_line, inbound_shipment: inbound,
          purchase_order_line: FactoryBot.create(:purchase_order_line, purchase_order: order, quantity:))
      end
    end
  end

  let(:published) { [] }

  before { allow(Contracts).to receive(:publish).and_wrap_original { |original, event| published << event; original.call(event) } }

  def line_input(line, accepted_quantity) = { inbound_shipment_line_id: line.id, accepted_quantity: }

  def full_input = [ line_input(inbound_lines[0], 3), line_input(inbound_lines[1], 2) ]

  def record(inbound_shipment_id: inbound.id, lines: full_input)
    Tenancy.with_tenant(buyer.id) { described_class.record(actor, inbound_shipment_id:, lines:) }
  end

  def inspections = Tenancy.with_tenant(buyer.id) { Purchasing::ReceiptInspection.order(:id).to_a }

  def accepted_quantities
    Tenancy.with_tenant(buyer.id) { Purchasing::ReceiptInspectionLine.order(:inbound_shipment_line_id).pluck(:inbound_shipment_line_id, :accepted_quantity) }
  end

  def find_order = Tenancy.with_tenant(buyer.id) { Purchasing::PurchaseOrders.find(actor, order.id) }

  # 発注側テナントが登録した「検収完了」のジョブ。ほかの example のテナントのジョブを数えない
  def inspected_jobs
    enqueued_event_jobs.map { _1.arguments.fetch("arguments") }
      .select { |name, payload| name == "Contracts::ReceiptInspected" && payload.fetch("buyer_tenant_id") == buyer.id }
  end

  def failure_of(result) = result.failures.map { [ _1.code, _1.path ] }

  def expect_nothing_written
    expect(inspections).to be_empty
    expect(accepted_quantities).to be_empty
    expect(published).to be_empty
    expect(find_order.status).to eq(:inbound)
  end

  it "登録した日を検収日にして明細ごとの検収数量を残し、「検収完了」を出す。発注は検収済になる" do
    travel_to(Time.zone.parse("2026-10-21 10:00")) { expect(record).to be_success }

    inspection = inspections.sole
    expect(inspection).to have_attributes(owner_tenant_id: buyer.id, inbound_shipment_id: inbound.id,
      inspected_on: Date.new(2026, 10, 21))
    expect(accepted_quantities).to match_array([ [ inbound_lines[0].id, 3 ], [ inbound_lines[1].id, 2 ] ])
    expect(published.sole).to have_attributes(class: Contracts::ReceiptInspected, shipment_id: inbound.shipment_id,
      purchase_order_id: order.id, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id, inspected_on: "2026-10-21",
      lines: match_array([
        { "purchase_order_line_id" => inbound_lines[0].purchase_order_line_id, "accepted_quantity" => 3 },
        { "purchase_order_line_id" => inbound_lines[1].purchase_order_line_id, "accepted_quantity" => 2 }
      ]))
    expect(find_order.status).to eq(:inspected)
  end

  it "成功の値は、検収済になった発注である" do
    expect(record.value).to have_attributes(id: order.id, status: :inspected)
  end

  it "検収数量 0（全量の不合格）と、出荷数量ちょうどの検収数量を受け付ける" do
    expect(record(lines: [ line_input(inbound_lines[0], 0), line_input(inbound_lines[1], 2) ])).to be_success

    expect(accepted_quantities).to match_array([ [ inbound_lines[0].id, 0 ], [ inbound_lines[1].id, 2 ] ])
  end

  it "明細を入力と違う順に並べても受け付ける" do
    expect(record(lines: full_input.reverse)).to be_success
  end

  it "出荷数量を超える検収数量は INVALID_INPUT で、その明細を指す" do
    result = record(lines: [ line_input(inbound_lines[0], 3), line_input(inbound_lines[1], 3) ])

    expect(failure_of(result)).to eq([ [ :invalid_input, [ :lines, 1, :accepted_quantity ] ] ])
    expect_nothing_written
  end

  [ -1, nil, 1.5 ].each do |quantity|
    it "検収数量 #{quantity.inspect} は INVALID_INPUT で、その明細を指す" do
      result = record(lines: [ line_input(inbound_lines[0], quantity), line_input(inbound_lines[1], 2) ])

      expect(failure_of(result)).to eq([ [ :invalid_input, [ :lines, 0, :accepted_quantity ] ] ])
      expect_nothing_written
    end
  end

  it "明細の省略は INVALID_INPUT で、明細全体を指す" do
    result = record(lines: [ line_input(inbound_lines[0], 3) ])

    expect(failure_of(result)).to eq([ [ :invalid_input, [ :lines ] ] ])
    expect_nothing_written
  end

  it "明細が空なら INVALID_INPUT で、明細全体を指す" do
    expect(failure_of(record(lines: []))).to eq([ [ :invalid_input, [ :lines ] ] ])
    expect_nothing_written
  end

  it "同じ明細の重複は INVALID_INPUT で、2 つ目の明細を指す" do
    result = record(lines: [ *full_input, line_input(inbound_lines[1], 1) ])

    expect(failure_of(result)).to eq([ [ :invalid_input, [ :lines, 2, :inbound_shipment_line_id ] ] ])
    expect_nothing_written
  end

  it "別の入荷の明細は INVALID_INPUT で、その明細を指す" do
    other_line = Tenancy.with_tenant(buyer.id) { FactoryBot.create(:inbound_shipment_line) }

    result = record(lines: [ line_input(other_line, 1), *full_input ])

    expect(failure_of(result)).to eq([ [ :invalid_input, [ :lines, 0, :inbound_shipment_line_id ] ] ])
    expect_nothing_written
  end

  it "明細が上限の 100 件を超えれば、中身を見ずに INVALID_INPUT で、明細全体を指す" do
    result = record(lines: Array.new(described_class::MAX_LINES + 1) { line_input(inbound_lines[0], 1) })

    expect(failure_of(result)).to eq([ [ :invalid_input, [ :lines ] ] ])
    expect_nothing_written
  end

  it "同じ入荷への 2 回目の検収は CONFLICT で、検収も「検収完了」のジョブも 1 件のまま" do
    record

    expect(failure_of(record(lines: [ line_input(inbound_lines[0], 0), line_input(inbound_lines[1], 0) ])))
      .to eq([ [ :conflict, nil ] ])
    expect(inspections.size).to eq(1)
    expect(accepted_quantities).to match_array([ [ inbound_lines[0].id, 3 ], [ inbound_lines[1].id, 2 ] ])
    expect(published.size).to eq(1)
    expect(inspected_jobs.size).to eq(1)
  end

  it "検収済の入荷への 2 回目は、入力が誤っていても入力を確かめる前に CONFLICT になる" do
    record

    expect(failure_of(record(lines: []))).to eq([ [ :conflict, nil ] ])
  end

  it "見えない入荷は NOT_FOUND" do
    other = FactoryBot.create(:tenant)
    others_inbound = Tenancy.with_tenant(other.id) { FactoryBot.create(:inbound_shipment) }

    [ SecureRandom.uuid, others_inbound.id, inbound.shipment_id ].each do |id|
      expect(failure_of(record(inbound_shipment_id: id))).to eq([ [ :not_found, [ :inbound_shipment_id ] ] ])
    end
    expect_nothing_written
  end

  it "取引関係が失効していても、連結済みの発注の入荷は検収できる" do
    # docs/architecture/context-map.md「取引関係の失効」の閉じないもの
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:partnership, :revoked, buyer_tenant_id: buyer.id, permissions: %w[place_orders view_shipments])
    end

    expect(record).to be_success
  end
end
