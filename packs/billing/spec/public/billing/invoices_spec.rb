require "rails_helper"

# 受注側が自社の請求書・税率ごとの集計・請求対象明細を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）。
# 一覧は親を 2 件以上作って読む（docs/architecture/graphql-schema.md「ページングと N+1」）
RSpec.describe "請求の読み取り" do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:customers) { FactoryBot.create_list(:tenant, 2) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:draft) do
    as_supplier do
      FactoryBot.create(:invoice, customer_tenant_id: customers[0].id, subtotal: 300, tax_total: 30).tap do |invoice|
        FactoryBot.create(:invoice_tax_summary, invoice:, tax_rate_percent: 10, taxable_amount: 300, tax_amount: 30)
        FactoryBot.create_list(:billable_item, 2, invoice:, customer_tenant_id: customers[0].id, unit_price: 150)
      end
    end
  end
  let!(:issued) do
    as_supplier do
      FactoryBot.create(:invoice, :issued, customer_tenant_id: customers[1].id, subtotal: 200, tax_total: 16).tap do |invoice|
        FactoryBot.create(:invoice_tax_summary, invoice:, tax_rate_percent: 8, taxable_amount: 200, tax_amount: 16)
        FactoryBot.create(:billable_item, invoice:, customer_tenant_id: customers[1].id, unit_price: 100, quantity: 2, tax_rate_percent: 8)
      end
    end
  end
  let!(:unbilled) do
    customers.map { |customer| as_supplier { FactoryBot.create(:billable_item, customer_tenant_id: customer.id, quantity: 3) } }
  end
  # 相手テナントが自社の請求として持つ行。受注側の自社の一覧には混ざらない
  let!(:foreign) do
    Tenancy.with_tenant(customers[0].id) do
      FactoryBot.create(:invoice).tap { FactoryBot.create(:billable_item, invoice: _1, customer_tenant_id: supplier.id) }
    end
  end

  def as_supplier(&) = Tenancy.with_tenant(supplier.id, &)

  describe Billing::Invoices do
    it "一覧は自社の請求書を新しい順に返し、下書きは番号が空で状態が DRAFT になる" do
      page = as_supplier { described_class.list(actor, first: 10, after: nil) }

      expect(page.values.map { [ _1.id, _1.state, _1.invoice_number, _1.total ] })
        .to eq([ [ issued.id, :issued, issued.invoice_number, 216 ], [ draft.id, :draft, nil, 330 ] ])
    end

    it "操作者を渡さなければ、行を引かずに失敗する" do
      expect { as_supplier { described_class.list(nil, first: 10, after: nil) } }.to raise_error(ArgumentError, "actor is required")
    end

    it "1 件を引き、見えない ID は nil になる" do
      expect(as_supplier { described_class.find(actor, draft.id) }).to have_attributes(customer_tenant_id: customers[0].id, state: :draft)
      expect(as_supplier { described_class.find(actor, foreign.id) }).to be_nil
    end

    it "請求書 ID ごとの税率ごとの集計を返し、見えない請求書は空になる" do
      summaries = as_supplier { described_class.tax_summaries_for(actor, [ draft.id, issued.id, foreign.id ]) }

      expect(summaries.transform_values { |values| values.map { [ _1.tax_rate_percent, _1.taxable_amount, _1.tax_amount ] } })
        .to eq(draft.id => [ [ 10, 300, 30 ] ], issued.id => [ [ 8, 200, 16 ] ], foreign.id => [])
    end
  end

  describe Billing::BillableItems do
    it "一覧は自社の未請求明細だけを返し、取引先で絞れる" do
      all = as_supplier { described_class.list(actor, customer_tenant_id: nil, first: 10, after: nil) }
      one = as_supplier { described_class.list(actor, customer_tenant_id: customers[1].id, first: 10, after: nil) }

      expect(all.values.map(&:id)).to match_array(unbilled.map(&:id))
      expect(all.values.map(&:amount)).to eq([ 360, 360 ])
      expect(one.values.map(&:id)).to eq([ unbilled[1].id ])
    end

    it "相手テナントや存在しないテナントで絞ると空になる" do
      [ supplier.id, SecureRandom.uuid ].each do |id|
        expect(as_supplier { described_class.list(actor, customer_tenant_id: id, first: 10, after: nil) }.values).to be_empty
      end
    end

    it "請求書の明細を返し、見えない請求書は空になる" do
      draft_items = as_supplier { described_class.for_invoice(actor, draft.id, first: 10, after: nil) }
      issued_items = as_supplier { described_class.for_invoice(actor, issued.id, first: 10, after: nil) }

      expect(draft_items.values.map { [ _1.invoice_id, _1.amount ] }).to eq([ [ draft.id, 150 ] ] * 2)
      expect(issued_items.values.map { [ _1.invoice_id, _1.tax_rate_percent, _1.amount ] }).to eq([ [ issued.id, 8, 200 ] ])
      expect(as_supplier { described_class.for_invoice(actor, foreign.id, first: 10, after: nil) }.values).to be_empty
    end
  end
end
