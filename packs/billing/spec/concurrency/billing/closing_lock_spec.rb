require "rails_helper"
require_relative "../../../../../spec/support/events"

# 締めの直列化（docs/architecture/data-model.md「請求（`billing`）」）。締めと下書きの破棄と確定は請求条件の行をロックし、
# 同じ取引先の締めを直列にする。「請求対象確定」の受け手はこのロックを取らないので、締めの最中に届いた検収は待たずに
# 未請求の明細として残り、次の締めで集まる
RSpec.describe "締めの競合" do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:customers) { FactoryBot.create_list(:tenant, 2) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "admin", partner_code: "") }

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
      %w[invoice_tax_summaries billable_items invoices invoice_sequences billing_terms partnership_grants partnerships])
  end

  def as_supplier(&) = Tenancy.with_tenant(supplier.id, &)

  def close(customer = customers[0], closing_date: Date.new(2026, 9, 20))
    Billing::Closing.close(actor, customer_tenant_id: customer.id, closing_date:)
  end

  def drafts = as_supplier { Billing::Invoice.draft.order(:id).pluck(:customer_tenant_id) }

  def issued_numbers = as_supplier { Billing::Invoice.issued.order(:id).pluck(:invoice_number) }

  def issue(invoice_id) = Billing::Closing.issue(actor, invoice_id:)

  def discard(invoice_id) = Billing::Closing.discard(actor, invoice_id:)

  # 受注側テナントが登録した「請求書発行」のペイロード。ほかの example のテナントのジョブを数えない
  def published_payloads
    enqueued_event_jobs.map { _1.arguments.fetch("arguments") }
      .select { |name, payload| name == "Contracts::InvoiceIssued" && payload.fetch("supplier_tenant_id") == supplier.id }
      .map(&:second)
  end

  def published_invoices = published_payloads.map { _1.fetch("invoice_id") }
  def published_lines = published_payloads.flat_map { _1.fetch("lines") }

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

  it "同じ下書きの 2 つの破棄は、後の破棄が請求条件の行ロックを待ち、先のコミットの後に NOT_FOUND になる" do
    draft = as_supplier { close }.value

    first, release, first_thread = hold_open(supplier.id) { Billing::Closing.discard(actor, invoice_id: draft.id) }
    expect(first).to be_success

    second_thread = in_thread(supplier.id) { Billing::Closing.discard(actor, invoice_id: draft.id) }
    expect(blocked_on_lock?(second_thread, by: first_thread)).to be(true)

    commit(release, first_thread)
    expect(finish(second_thread).failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :invoice_id ] ] ])
    expect(drafts).to be_empty
    expect(as_supplier { Billing::BillableItem.where(customer_tenant_id: customers[0].id).pluck(:invoice_id) }).to eq([ nil ])
  end

  it "締めが明細を集めた後に届いた前の期間の検収は、締めを待たずに未請求で残り、次の締めで集まる" do
    # 締めが明細を集めてから請求書に結ぶまでの間に、別の接続で「請求対象確定」を受けてコミットさせる
    allow(Billing::Closing).to receive(:create_draft).and_wrap_original do |original, *args|
      receiver_thread = in_thread(supplier.id) { Billing::SalesEventReceiver.handle(late_inspection) }
      finish(receiver_thread)
      original.call(*args)
    end

    first = as_supplier { close }
    expect(first.value.total).to eq(132)

    late = as_supplier { Billing::BillableItem.find_by!(item_name: "遅れた検収") }
    expect(late.invoice_id).to be_nil
    as_supplier { Billing::Invoice.find(first.value.id).update!(issued_at: Time.current, invoice_number: "INV-#{SecureRandom.hex(4)}") }

    second = as_supplier { close(closing_date: Date.new(2026, 10, 20)) }
    expect(second.value).to have_attributes(period_start: Date.new(2026, 9, 21), total: 110)
    expect(as_supplier { late.reload.invoice_id }).to eq(second.value.id)
  end

  it "締めが開いている間も、「請求対象確定」の受け手は請求条件の行ロックを待たない" do
    first, release, first_thread = hold_open(supplier.id) { close }
    expect(first).to be_success

    receiver_thread = in_thread(supplier.id) { Billing::SalesEventReceiver.handle(late_inspection) }
    expect(blocked_on_lock?(receiver_thread, by: first_thread)).to be(false)
    finish(receiver_thread)
    commit(release, first_thread)
    expect(as_supplier { Billing::BillableItem.find_by!(item_name: "遅れた検収").invoice_id }).to be_nil
  end

  describe "確定" do
    let!(:draft) { as_supplier { close }.value }

    it "確定が開いている間は同じ下書きの破棄が請求条件の行ロックを待ち、確定のコミットの後に CONFLICT になる" do
      issued, release, issue_thread = hold_open(supplier.id) { issue(draft.id) }
      expect(issued).to be_success

      discard_thread = in_thread(supplier.id) { discard(draft.id) }
      expect(blocked_on_lock?(discard_thread, by: issue_thread)).to be(true)

      commit(release, issue_thread)
      expect(finish(discard_thread).failures.map(&:code)).to eq([ :conflict ])
      expect(issued_numbers).to eq([ "INV-000001" ])
      expect(published_invoices).to eq([ draft.id ])
    end

    it "破棄が開いている間は同じ下書きの確定がロックを待ち、破棄のコミットの後に NOT_FOUND になって「請求書発行」を出さない" do
      discarded, release, discard_thread = hold_open(supplier.id) { discard(draft.id) }
      expect(discarded).to be_success

      issue_thread = in_thread(supplier.id) { issue(draft.id) }
      expect(blocked_on_lock?(issue_thread, by: discard_thread)).to be(true)

      commit(release, discard_thread)
      expect(finish(issue_thread).failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :invoice_id ] ] ])
      expect(issued_numbers).to be_empty
      expect(published_invoices).to be_empty
    end

    it "確定が開いている間は同じ取引先の締めが請求条件の行ロックを待ち、確定のコミットの後に次の期間を締められる" do
      as_supplier { FactoryBot.create(:billable_item, customer_tenant_id: customers[0].id, inspected_on: Date.new(2026, 10, 10)) }

      issued, release, issue_thread = hold_open(supplier.id) { issue(draft.id) }
      expect(issued).to be_success

      close_thread = in_thread(supplier.id) { close(closing_date: Date.new(2026, 10, 20)) }
      expect(blocked_on_lock?(close_thread, by: issue_thread)).to be(true)

      commit(release, issue_thread)
      expect(finish(close_thread).value).to have_attributes(period_start: Date.new(2026, 9, 21), total: 132)
      expect(drafts).to eq([ customers[0].id ])
    end

    # 公開 API を通らない書き込みも、確定と競うと DB のトリガーが請求書の行の共有ロックで待ってから拒む
    describe "確定と、公開 API を通らない明細の書き換え" do
      def bound_items = as_supplier { Billing::BillableItem.where(invoice_id: draft.id).order(:id).pluck(:id, :quantity) }

      it "確定が開いている間は、結んだ明細の書き換えが請求書の行ロックを待ち、確定のコミットの後に拒まれる" do
        before_items = bound_items
        issued, release, issue_thread = hold_open(supplier.id) { issue(draft.id) }
        expect(issued).to be_success

        writer = in_thread(supplier.id) { Billing::BillableItem.where(invoice_id: draft.id).update_all(quantity: 2) }
        expect(blocked_on_lock?(writer, by: issue_thread)).to be(true)

        commit(release, issue_thread)
        expect { finish(writer) }.to raise_error(ActiveRecord::StatementInvalid, /確定した請求書は変えられない/)
        expect(bound_items).to eq(before_items)
      end

      it "確定が開いている間は、未請求の明細を結ぶ書き換えが請求書の行ロックを待ち、確定のコミットの後に拒まれる" do
        unbilled = as_supplier { FactoryBot.create(:billable_item, customer_tenant_id: customers[0].id, inspected_on: Date.new(2026, 10, 1)) }
        before_items = bound_items
        issued, release, issue_thread = hold_open(supplier.id) { issue(draft.id) }
        expect(issued).to be_success

        writer = in_thread(supplier.id) { Billing::BillableItem.where(id: unbilled.id).update_all(invoice_id: draft.id) }
        expect(blocked_on_lock?(writer, by: issue_thread)).to be(true)

        commit(release, issue_thread)
        expect { finish(writer) }.to raise_error(ActiveRecord::StatementInvalid, /確定した請求書は変えられない/)
        expect(bound_items).to eq(before_items)
      end

      it "明細の書き換えが開いている間は、確定が請求書の行ロックを待ち、書き換えた明細で「請求書発行」を出す" do
        written, release, writer = hold_open(supplier.id) { Billing::BillableItem.where(invoice_id: draft.id).update_all(quantity: 2) }
        expect(written).to eq(1)

        issue_thread = in_thread(supplier.id) { issue(draft.id) }
        expect(blocked_on_lock?(issue_thread, by: writer)).to be(true)

        commit(release, writer)
        expect(finish(issue_thread)).to be_success
        expect(published_lines.map { _1.fetch("quantity") }).to eq([ 2 ])
      end
    end

    it "同じ下書きの 2 つの確定は、後の確定がロックを待ち、先のコミットの後に CONFLICT になって番号を 1 つだけ振る" do
      first, release, first_thread = hold_open(supplier.id) { issue(draft.id) }
      expect(first).to be_success

      second_thread = in_thread(supplier.id) { issue(draft.id) }
      expect(blocked_on_lock?(second_thread, by: first_thread)).to be(true)

      commit(release, first_thread)
      expect(finish(second_thread).failures.map(&:code)).to eq([ :conflict ])
      expect(issued_numbers).to eq([ "INV-000001" ])
      expect(published_invoices).to eq([ draft.id ])
    end
  end
end
