require "rails_helper"

# 請求の締めと下書きの破棄。締めは、締め日以前に検収された取引先の未請求明細をすべて集めて下書きを作り、
# 消費税を税率ごとに 1 回だけ切り捨てる。入力と状態は上から順に確かめ、最初に当たった結果を返す
# （docs/architecture/data-model.md「請求（`billing`）」、docs/architecture/context-map.md「検収と請求の流れ」5）
RSpec.describe Billing::Closing do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:customer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:partnership) { as_supplier { FactoryBot.create(:partnership, buyer_tenant_id: customer.id) } }
  let!(:term) { as_supplier { FactoryBot.create(:billing_term, customer_tenant_id: customer.id, closing_day: 20) } }

  def as_supplier(&) = Tenancy.with_tenant(supplier.id, &)

  def item(inspected_on, **attributes)
    as_supplier do
      FactoryBot.create(:billable_item, customer_tenant_id: customer.id, inspected_on: Date.iso8601(inspected_on), **attributes)
    end
  end

  def close(closing_date, customer_tenant_id: customer.id)
    as_supplier { described_class.close(actor, customer_tenant_id:, closing_date: Date.iso8601(closing_date)) }
  end

  def discard(invoice_id) = as_supplier { described_class.discard(actor, invoice_id:) }

  def failure_of(result) = result.failures.map { [ _1.code, _1.path ] }

  def invoices = as_supplier { Billing::Invoice.order(:id).to_a }

  # 請求書 ID ごとの明細 ID
  def billed = as_supplier { Billing::BillableItem.order(:id).pluck(:id, :invoice_id).to_h }

  # 前の締めで確定した請求書。確定の公開 API が無いので、確定の状態の行を直接作る
  def issued_invoice(period_end)
    as_supplier do
      FactoryBot.create(:invoice, :issued, customer_tenant_id: customer.id, period_start: Date.iso8601(period_end).beginning_of_month,
        period_end: Date.iso8601(period_end))
    end
  end

  describe ".close" do
    it "締め日以前に検収された取引先の未請求明細をすべて集めて、番号の無い下書きを作る" do
      collected = [ item("2026-09-05"), item("2026-09-20") ]
      after_closing = item("2026-09-21")
      other_customer = as_supplier { FactoryBot.create(:billable_item, inspected_on: Date.new(2026, 9, 10)) }
      billed_before = item("2026-09-01", invoice: issued_invoice("2026-08-20"))

      result = close("2026-09-20")

      expect(result).to be_success
      invoice = invoices.find(&:draft?)
      expect(result.value).to have_attributes(id: invoice.id, customer_tenant_id: customer.id, invoice_number: nil, state: :draft,
        period_end: Date.new(2026, 9, 20), issued_at: nil)
      expect(billed).to eq(collected.to_h { [ _1.id, invoice.id ] }
        .merge(after_closing.id => nil, other_customer.id => nil, billed_before.id => billed_before.invoice_id))
    end

    it "前の請求書が無ければ、期間の始まりは集めた明細の最も古い検収日になる" do
      item("2026-08-03")
      item("2026-09-12")

      expect(close("2026-09-20").value).to have_attributes(period_start: Date.new(2026, 8, 3), period_end: Date.new(2026, 9, 20))
    end

    it "期間の始まりは前の請求書（下書きを除く）の終わりの翌日で、それより前の遅れて届いた検収も集める" do
      issued_invoice("2026-08-20")
      late = item("2026-08-15")
      current = item("2026-09-01")

      result = close("2026-09-20")

      expect(result.value).to have_attributes(period_start: Date.new(2026, 8, 21), period_end: Date.new(2026, 9, 20))
      expect(billed.values_at(late.id, current.id)).to eq([ result.value.id ] * 2)
    end

    it "締めの後に届いた前の期間の検収は次の締めで集まり、次の締め日より後の検収は集まらない" do
      item("2026-09-10")
      first = close("2026-09-20").value
      as_supplier { Billing::Invoice.find(first.id).update!(issued_at: Time.current, invoice_number: "INV-1") }
      late = item("2026-09-18")
      current = item("2026-10-05")
      next_period = item("2026-10-21")

      second = close("2026-10-20").value

      expect(second).to have_attributes(period_start: Date.new(2026, 9, 21), period_end: Date.new(2026, 10, 20))
      expect(billed.values_at(late.id, current.id, next_period.id)).to eq([ second.id, second.id, nil ])
    end

    it "消費税は請求書・税率ごとに 1 回だけ切り捨て、明細ごとに丸めた合計とは異なる" do
      # 10% の 105 円 × 3 明細は、明細ごとなら 10 円 × 3 = 30 円、まとめると 31.5 円 → 31 円。
      # 8% の 99 円 × 2 明細は、明細ごとなら 7 円 × 2 = 14 円、まとめると 15.84 円 → 15 円
      3.times { item("2026-09-10", unit_price: 105, tax_rate_percent: 10) }
      2.times { item("2026-09-11", unit_price: 99, tax_rate_percent: 8) }
      item("2026-09-12", unit_price: 50, quantity: 3, tax_rate_percent: 8)

      invoice = close("2026-09-20").value

      per_line = as_supplier { Billing::BillableItem.all.sum { _1.amount * _1.tax_rate_percent / 100 } }
      expect(invoice).to have_attributes(subtotal: 315 + 198 + 150, tax_total: 31 + 27, total: 663 + 58)
      expect(per_line).to eq(30 + 14 + 12)
      expect(as_supplier { Billing::InvoiceTaxSummary.where(invoice_id: invoice.id).order(:tax_rate_percent).pluck(:tax_rate_percent, :taxable_amount, :tax_amount) })
        .to eq([ [ 8, 348, 27 ], [ 10, 315, 31 ] ])
    end

    describe "末日締め（31）" do
      before { as_supplier { term.update!(closing_day: 31) } }

      { "2 月（平年）" => "2026-02-28", "2 月（うるう年）" => "2028-02-29", "30 日の月" => "2026-04-30", "31 日の月" => "2026-05-31" }
        .each do |month, date|
          it "#{month}は月末の #{date} で締められる" do
            item(Date.iso8601(date).beginning_of_month.iso8601)

            expect(close(date)).to be_success
          end
        end

      %w[2026-02-27 2028-02-28 2026-04-29 2026-05-30].each do |date|
        it "月末でない #{date} は INVALID_INPUT" do
          item(Date.iso8601(date).beginning_of_month.iso8601)

          expect(failure_of(close(date))).to eq([ [ :invalid_input, [ :closing_date ] ] ])
          expect(invoices).to be_empty
        end
      end
    end

    describe "失敗" do
      before { item("2026-09-10") }

      it "自社が受注側の取引関係の相手でない取引先は、請求条件があっても NOT_FOUND" do
        stranger = FactoryBot.create(:tenant)
        as_supplier { FactoryBot.create(:billing_term, customer_tenant_id: stranger.id, closing_day: 20) }

        expect(failure_of(close("2026-09-20", customer_tenant_id: stranger.id))).to eq([ [ :not_found, [ :customer_tenant_id ] ] ])
        expect(failure_of(close("2026-09-20", customer_tenant_id: SecureRandom.uuid))).to eq([ [ :not_found, [ :customer_tenant_id ] ] ])
        expect(invoices).to be_empty
      end

      it "失効した取引関係の相手は締められる。失効の前の取引も請求まで進むからである" do
        as_supplier { partnership.update!(status: "revoked", revoked_at: Time.current) }

        expect(close("2026-09-20")).to be_success
      end

      it "請求条件の無い取引先は NOT_FOUND" do
        as_supplier { term.destroy! }

        expect(failure_of(close("2026-09-20"))).to eq([ [ :not_found, [ :customer_tenant_id ] ] ])
        expect(invoices).to be_empty
      end

      it "締め日が請求条件の締め日に当たらなければ INVALID_INPUT" do
        expect(failure_of(close("2026-09-21"))).to eq([ [ :invalid_input, [ :closing_date ] ] ])
        expect(invoices).to be_empty
      end

      it "取引先に下書きがあれば CONFLICT で、新しい下書きを作らない" do
        draft = close("2026-09-20").value
        item("2026-10-01")

        expect(failure_of(close("2026-10-20"))).to eq([ [ :conflict, nil ] ])
        expect(invoices.map(&:id)).to eq([ draft.id ])
      end

      it "締め日が前の請求書（下書きを除く）の期間の終わり以前なら INVALID_INPUT。同じ日も拒む" do
        issued_invoice("2026-09-20")

        expect(failure_of(close("2026-09-20"))).to eq([ [ :invalid_input, [ :closing_date ] ] ])
        expect(failure_of(close("2026-08-20"))).to eq([ [ :invalid_input, [ :closing_date ] ] ])
        expect(invoices.count(&:draft?)).to eq(0)
      end

      it "締め日以前に検収された未請求明細が 0 件なら CONFLICT で、請求書を作らない" do
        expect(failure_of(close("2026-08-20"))).to eq([ [ :conflict, nil ] ])
        expect(invoices).to be_empty
      end
    end

    describe "確かめる順" do
      before { item("2026-09-10") }

      it "締め日の誤りは、下書きの有無より先に INVALID_INPUT になる" do
        close("2026-09-20")

        expect(failure_of(close("2026-10-21"))).to eq([ [ :invalid_input, [ :closing_date ] ] ])
      end

      it "下書きがあれば、前の請求書との重なりより先に CONFLICT になる" do
        close("2026-09-20")
        issued_invoice("2026-10-20")

        expect(failure_of(close("2026-10-20"))).to eq([ [ :conflict, nil ] ])
      end

      it "前の請求書との重なりは、明細が 0 件であることより先に INVALID_INPUT になる" do
        issued_invoice("2026-09-20")
        as_supplier { Billing::BillableItem.delete_all }

        expect(failure_of(close("2026-09-20"))).to eq([ [ :invalid_input, [ :closing_date ] ] ])
      end
    end
  end

  describe ".discard" do
    it "下書きを消し、集めた明細を未請求に戻す。同じ締め日で締め直せる" do
      items = [ item("2026-09-10"), item("2026-09-11", tax_rate_percent: 8) ]
      draft = close("2026-09-20").value

      result = discard(draft.id)

      expect(result).to be_success
      expect(result.value).to eq(draft.id)
      expect(invoices).to be_empty
      expect(as_supplier { Billing::InvoiceTaxSummary.count }).to eq(0)
      expect(billed.values_at(*items.map(&:id))).to eq([ nil, nil ])
      expect(close("2026-09-20")).to be_success
    end

    it "発行済みの請求書は CONFLICT で、明細を戻さない" do
      issued = issued_invoice("2026-09-20")
      billed_item = item("2026-09-10", invoice: issued)

      expect(failure_of(discard(issued.id))).to eq([ [ :conflict, nil ] ])
      expect(billed.fetch(billed_item.id)).to eq(issued.id)
    end

    it "見えない請求書は NOT_FOUND" do
      other = Tenancy.with_tenant(customer.id) { FactoryBot.create(:invoice) }

      expect(failure_of(discard(other.id))).to eq([ [ :not_found, [ :invoice_id ] ] ])
      expect(Tenancy.with_tenant(customer.id) { Billing::Invoice.exists?(other.id) }).to be(true)
    end
  end
end
