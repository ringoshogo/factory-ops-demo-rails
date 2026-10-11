require "rails_helper"
require_relative "../../../../../spec/support/events"
require_relative "../../../../../spec/support/shared_examples/idempotent_receiver"

# 「請求書発行」の購買の受け手。発注側テナントの名義で、請求書の値を受領請求書と明細に写す。冪等キーは請求書 ID
# （docs/architecture/context-map.md「検収と請求の流れ」6、docs/architecture/data-model.md「イベントの受け口と冪等キー」）
RSpec.describe Purchasing::BillingEventReceiver do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let!(:lines) { Tenancy.with_tenant(buyer.id) { FactoryBot.create_list(:purchase_order_line, 2) } }
  let(:event) do
    Contracts::InvoiceIssued.new(invoice_id: SecureRandom.uuid, supplier_tenant_id: supplier.id, buyer_tenant_id: buyer.id,
      invoice_number: "INV-000001", period_start: "2026-09-10", period_end: "2026-09-20", issued_on: "2026-10-12",
      subtotal: "513", tax_total: "46", total: "559",
      lines: [
        { "purchase_order_line_id" => lines[0].id, "item_name" => "六角ボルト M8", "unit_price" => "105", "quantity" => 3,
          "tax_rate_percent" => 10, "amount" => "315" },
        { "purchase_order_line_id" => lines[1].id, "item_name" => "ナット M8", "unit_price" => "99", "quantity" => 2,
          "tax_rate_percent" => 8, "amount" => "198" }
      ])
  end

  def handle(event) = Tenancy.with_tenant(buyer.id) { described_class.handle(event) }

  def received
    Tenancy.with_tenant(buyer.id) do
      Purchasing::ReceivedInvoice.includes(:lines).order(:id).map do |invoice|
        invoice.attributes.symbolize_keys.slice(:owner_tenant_id, :invoice_id, :supplier_tenant_id, :invoice_number, :period_start,
          :period_end, :issued_on, :subtotal, :tax_total, :total)
          .merge(lines: invoice.lines.map { _1.attributes.symbolize_keys.slice(:purchase_order_line_id, :item_name, :unit_price, :quantity,
            :tax_rate_percent, :amount) })
      end
    end
  end

  it_behaves_like "冪等な受け手" do
    # 受注側が、相手の購買へ出す
    let(:publish_event) { -> { Tenancy.with_tenant(supplier.id) { Contracts.publish(event) } } }
    let(:written_rows) { -> { Tenancy.with_tenant(buyer.id) { Purchasing::ReceivedInvoice.count + Purchasing::ReceivedInvoiceLine.count } } }
  end

  it "発注側テナントの名義で、請求書の値と明細を受領請求書に写す" do
    handle(event)

    expect(received).to eq([ {
      owner_tenant_id: buyer.id, invoice_id: event.invoice_id, supplier_tenant_id: supplier.id, invoice_number: "INV-000001",
      period_start: Date.new(2026, 9, 10), period_end: Date.new(2026, 9, 20), issued_on: Date.new(2026, 10, 12),
      subtotal: 513, tax_total: 46, total: 559,
      lines: [
        { purchase_order_line_id: lines[0].id, item_name: "六角ボルト M8", unit_price: 105, quantity: 3, tax_rate_percent: 10, amount: 315 },
        { purchase_order_line_id: lines[1].id, item_name: "ナット M8", unit_price: 99, quantity: 2, tax_rate_percent: 8, amount: 198 }
      ]
    } ])
  end

  it "別の請求書は、別の受領請求書として写す" do
    handle(event)
    handle(event.with(invoice_id: SecureRandom.uuid, invoice_number: "INV-000002"))

    expect(received.map { _1[:invoice_number] }).to eq(%w[INV-000001 INV-000002])
  end

  it "自社の発注明細でない明細を運ぶ請求書は、何も書かずに失敗する" do
    foreign_line = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:purchase_order_line) }
    lines = [ event.lines.first.merge("purchase_order_line_id" => foreign_line.id) ]

    expect { handle(event.with(lines:)) }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(received).to be_empty
  end

  it "配送表に無い種類のイベントは、何も書かずに ArgumentError で失敗する" do
    unexpected = Contracts::PartMatchPending.new(purchase_order_id: SecureRandom.uuid, buyer_tenant_id: buyer.id,
      supplier_tenant_id: supplier.id)

    expect { handle(unexpected) }.to raise_error(ArgumentError, "unexpected event: Contracts::PartMatchPending")
    expect(received).to be_empty
  end
end
