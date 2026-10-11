require "rails_helper"

# 同じ「請求書発行」が 2 つの配送で同時に届いたときの冪等（docs/architecture/context-map.md「検収と請求の流れ」6、
# docs/architecture/data-model.md「イベントの受け口と冪等キー」）。先の配送が受領請求書を書いてコミットする前は、
# 後の配送が請求書 ID の一意索引で待ち、先のコミットの後は何も書かずに終わる
RSpec.describe "同じ請求書発行の同時の配送" do
  self.use_transactional_tests = false

  let!(:buyer) { FactoryBot.create(:tenant) }
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:lines) { Tenancy.with_tenant(buyer.id) { FactoryBot.create_list(:purchase_order_line, 2) } }
  let(:event) do
    Contracts::InvoiceIssued.new(invoice_id: SecureRandom.uuid, supplier_tenant_id: supplier.id, buyer_tenant_id: buyer.id,
      invoice_number: "INV-000001", period_start: "2026-09-10", period_end: "2026-09-20", issued_on: "2026-10-12",
      subtotal: "240", tax_total: "24", total: "264",
      lines: lines.map do |line|
        { "purchase_order_line_id" => line.id, "item_name" => "六角ボルト M8", "unit_price" => "120", "quantity" => 1,
          "tax_rate_percent" => 10, "amount" => "120" }
      end)
  end

  after do
    delete_owned_rows([ buyer.id, supplier.id ], %w[received_invoice_lines received_invoices purchase_order_lines purchase_orders])
  end

  def receive = Purchasing::BillingEventReceiver.handle(event)

  it "後の配送は先の配送のコミットを待ち、受領請求書と明細は 1 回分だけ残る" do
    _, release, first = hold_open(buyer.id) { receive }

    second = in_thread(buyer.id) { receive }
    expect(blocked_on_lock?(second, by: first)).to be(true)

    commit(release, first)
    finish(second)
    expect(Tenancy.with_tenant(buyer.id) { [ Purchasing::ReceivedInvoice.count, Purchasing::ReceivedInvoiceLine.count ] }).to eq([ 1, 2 ])
  end
end
