require "rails_helper"
require_relative "../../../../../spec/support/concurrency"

# 締めの直列化（docs/architecture/data-model.md「請求（`billing`）」）。締めと下書きの破棄は請求条件の行をロックし、
# 同じ取引先の締めを直列にする。「請求対象確定」の受け手はこのロックを取らないので、締めの最中に届いた検収は待たずに
# 未請求の明細として残り、次の締めで集まる
RSpec.describe "締めの競合" do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:customers) { FactoryBot.create_list(:tenant, 2) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  before do
    as_supplier do
      customers.each do |customer|
        FactoryBot.create(:partnership, buyer_tenant_id: customer.id)
        FactoryBot.create(:billing_term, customer_tenant_id: customer.id, closing_day: 20)
        FactoryBot.create(:billable_item, customer_tenant_id: customer.id, inspected_on: Date.new(2026, 9, 10))
      end
    end
  end

  after do
    delete_owned_rows([ supplier.id, *customers.map(&:id) ],
      %w[invoice_tax_summaries billable_items invoices billing_terms partnership_grants partnerships])
  end

  def as_supplier(&) = Tenancy.with_tenant(supplier.id, &)

  def close(customer = customers[0], closing_date: Date.new(2026, 9, 20))
    Billing::Closing.close(actor, customer_tenant_id: customer.id, closing_date:)
  end

  def drafts = as_supplier { Billing::Invoice.draft.order(:id).pluck(:customer_tenant_id) }

  # 締めの最中に、受注の受け手から届く前の期間の検収
  def late_inspection
    Contracts::BillableItemConfirmed.new(supplier_tenant_id: supplier.id, buyer_tenant_id: customers[0].id, shipment_id: SecureRandom.uuid,
      sales_order_line_id: SecureRandom.uuid, purchase_order_line_id: SecureRandom.uuid, item_name: "遅れた検収", unit_price: "100",
      tax_rate_percent: 10, quantity: 1, inspected_on: "2026-09-15")
  end

  it "同じ取引先の 2 つの締めは、後の締めが請求条件の行ロックを待ち、先のコミットの後に CONFLICT になって下書きは 1 件だけできる" do
    first, release, first_thread = hold_open(supplier.id) { close }
    expect(first).to be_success

    second_thread = in_thread(supplier.id) { close }
    expect(blocked_on_lock?(second_thread, by: first_thread)).to be(true)

    expect(commit(release, first_thread)).to be_success
    expect(finish(second_thread).failures.map(&:code)).to eq([ :conflict ])
    expect(drafts).to eq([ customers[0].id ])
  end

  it "下書きの破棄が開いている間は同じ取引先の締めが待ち、破棄のコミットの後に締め直せる" do
    draft = as_supplier { close }.value

    discarded, release, discard_thread = hold_open(supplier.id) { Billing::Closing.discard(actor, invoice_id: draft.id) }
    expect(discarded).to be_success

    close_thread = in_thread(supplier.id) { close }
    expect(blocked_on_lock?(close_thread, by: discard_thread)).to be(true)

    commit(release, discard_thread)
    expect(finish(close_thread)).to be_success
    expect(drafts).to eq([ customers[0].id ])
  end

  it "別の取引先の締めは待たない" do
    first, release, first_thread = hold_open(supplier.id) { close(customers[0]) }
    expect(first).to be_success

    other_thread = in_thread(supplier.id) { close(customers[1]) }
    expect(blocked_on_lock?(other_thread, by: first_thread)).to be(false)
    expect(finish(other_thread)).to be_success

    commit(release, first_thread)
    expect(drafts).to match_array(customers.map(&:id))
  end

  it "締めの最中に届いた前の期間の検収は、締めを待たずに未請求で残り、次の締めで集まる" do
    first, release, first_thread = hold_open(supplier.id) { close }

    receiver_thread = in_thread(supplier.id) { Billing::SalesEventReceiver.handle(late_inspection) }
    expect(blocked_on_lock?(receiver_thread, by: first_thread)).to be(false)
    finish(receiver_thread)
    commit(release, first_thread)

    late = as_supplier { Billing::BillableItem.find_by!(item_name: "遅れた検収") }
    expect(late.invoice_id).to be_nil
    as_supplier { Billing::Invoice.find(first.value.id).update!(issued_at: Time.current, invoice_number: "INV-#{SecureRandom.hex(4)}") }

    second = as_supplier { close(closing_date: Date.new(2026, 10, 20)) }
    expect(second.value).to have_attributes(period_start: Date.new(2026, 9, 21), total: 110)
    expect(as_supplier { late.reload.invoice_id }).to eq(second.value.id)
  end
end
