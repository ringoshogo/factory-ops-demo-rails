require "rails_helper"

# 確定した請求書と、それに結んだ税率ごとの集計と明細は変えない（docs/architecture/data-model.md「請求（`billing`）」）。
# 公開 API を通らない書き込みも止めるため、DB のトリガーが拒む。ここでは SQL で直接書いて確かめる。
# 受領請求書の合計も CHECK 制約で守る（docs/architecture/data-model.md「購買（`purchasing`）」）
RSpec.describe "確定した請求書の不変" do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:customer) { FactoryBot.create(:tenant) }

  # 結んだ明細と集計を持つ確定した請求書と下書き、未請求の明細。確定は、下書きの issued_at と番号を埋める UPDATE で行う
  let!(:issued) { as_supplier { invoice_with_children.tap { _1.update!(issued_at: Time.current, invoice_number: "INV-000001") } } }
  let!(:draft) { as_supplier { invoice_with_children } }
  let!(:unbilled) { as_supplier { FactoryBot.create(:billable_item, customer_tenant_id: customer.id) } }

  def as_supplier(&) = Tenancy.with_tenant(supplier.id, &)

  def connection = ActiveRecord::Base.lease_connection

  def invoice_with_children
    FactoryBot.create(:invoice, customer_tenant_id: customer.id, subtotal: 120, tax_total: 12).tap do |invoice|
      FactoryBot.create(:invoice_tax_summary, invoice:, taxable_amount: 120, tax_amount: 12)
      FactoryBot.create(:billable_item, invoice:, customer_tenant_id: customer.id)
    end
  end

  def run(sql, *binds) = as_supplier { connection.exec_query(sql, "Spec", binds) }

  # 請求書ごとの、請求書の列と結んだ明細と集計の写し
  def snapshot(invoice)
    as_supplier do
      [ connection.select_rows("SELECT invoice_number, issued_at, subtotal, total FROM invoices WHERE id = $1", "Spec", [ invoice.id ]),
        connection.select_rows("SELECT id, unit_price, quantity FROM billable_items WHERE invoice_id = $1 ORDER BY id", "Spec", [ invoice.id ]),
        connection.select_rows("SELECT id, taxable_amount, tax_amount FROM invoice_tax_summaries WHERE invoice_id = $1 ORDER BY id",
          "Spec", [ invoice.id ]) ]
    end
  end

  def rejected = raise_error(ActiveRecord::StatementInvalid, /確定した請求書は変えられない/)

  describe "確定した請求書" do
    it "UPDATE と DELETE を拒み、下書きの UPDATE は通す" do
      before = snapshot(issued)

      expect { run("UPDATE invoices SET total = total + 1, subtotal = subtotal + 1 WHERE id = $1", issued.id) }.to rejected
      expect { run("UPDATE invoices SET issued_at = NULL, invoice_number = NULL WHERE id = $1", issued.id) }.to rejected
      expect { run("DELETE FROM invoices WHERE id = $1", issued.id) }.to rejected
      expect(snapshot(issued)).to eq(before)
      expect(run("UPDATE invoices SET total = total WHERE id = $1", draft.id).rows).to eq([])
      expect(run("SELECT count(*) FROM invoices WHERE id = $1", draft.id).rows).to eq([ [ 1 ] ])
    end
  end

  describe "結んだ税率ごとの集計" do
    it "INSERT・UPDATE・DELETE を拒み、下書きの集計への同じ操作は通す" do
      before = snapshot(issued)
      insert = "INSERT INTO invoice_tax_summaries (owner_tenant_id, invoice_id, tax_rate_percent, taxable_amount, tax_amount, " \
        "created_at, updated_at) VALUES ($1, $2, 8, 0, 0, now(), now())"

      expect { run(insert, supplier.id, issued.id) }.to rejected
      expect { run("UPDATE invoice_tax_summaries SET tax_amount = tax_amount + 1 WHERE invoice_id = $1", issued.id) }.to rejected
      expect { run("DELETE FROM invoice_tax_summaries WHERE invoice_id = $1", issued.id) }.to rejected
      expect(snapshot(issued)).to eq(before)

      run(insert, supplier.id, draft.id)
      run("UPDATE invoice_tax_summaries SET tax_amount = tax_amount + 1 WHERE invoice_id = $1", draft.id)
      run("DELETE FROM invoice_tax_summaries WHERE invoice_id = $1", draft.id)
      expect(snapshot(draft)[2]).to eq([])
    end
  end

  describe "結んだ明細" do
    it "UPDATE と DELETE と、確定した請求書に結ぶ INSERT を拒む" do
      before = snapshot(issued)

      expect { run("UPDATE billable_items SET quantity = quantity + 1 WHERE invoice_id = $1", issued.id) }.to rejected
      expect { run("UPDATE billable_items SET invoice_id = NULL WHERE invoice_id = $1", issued.id) }.to rejected
      expect { run("UPDATE billable_items SET invoice_id = $1 WHERE invoice_id = $2", draft.id, issued.id) }.to rejected
      expect { run("DELETE FROM billable_items WHERE invoice_id = $1", issued.id) }.to rejected
      expect {
        as_supplier { FactoryBot.create(:billable_item, invoice: issued, customer_tenant_id: customer.id) }
      }.to rejected
      expect(snapshot(issued)).to eq(before)
    end

    it "未請求の明細を確定した請求書へ結ぶ UPDATE を拒み、下書きへ結ぶ UPDATE と下書きから外す UPDATE は通す" do
      before = snapshot(issued)

      expect { run("UPDATE billable_items SET invoice_id = $1 WHERE id = $2", issued.id, unbilled.id) }.to rejected
      expect(snapshot(issued)).to eq(before)

      run("UPDATE billable_items SET invoice_id = $1 WHERE id = $2", draft.id, unbilled.id)
      expect(snapshot(draft)[1].map(&:first)).to include(unbilled.id)
      run("UPDATE billable_items SET invoice_id = NULL WHERE invoice_id = $1", draft.id)
      expect(snapshot(draft)[1]).to eq([])
    end
  end

  describe "受領請求書" do
    def create_received_invoice(**amounts) = Tenancy.with_tenant(customer.id) { FactoryBot.create(:received_invoice, **amounts) }

    it "合計が小計と税額の和でない行を、CHECK 制約が拒む" do
      expect(create_received_invoice(subtotal: 100, tax_total: 10, total: 110)).to be_persisted
      expect { create_received_invoice(subtotal: 100, tax_total: 10, total: 111) }
        .to raise_error(ActiveRecord::StatementInvalid, /received_invoices_total_sum/)
    end
  end
end
