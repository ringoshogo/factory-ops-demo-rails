require "rails_helper"

# ダッシュボードの未請求の合計。未請求の請求対象明細の単価 × 検収数量を税抜きで合計する
# （docs/architecture/graphql-schema.md「読み取りの一覧」）
RSpec.describe Billing::BillableItems do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  def unbilled_total = Tenancy.with_tenant(supplier.id) { described_class.unbilled_total(actor) }

  describe ".unbilled_total" do
    it "未請求の明細の単価 × 数量を税抜きで合計し、請求書に結んだ明細を数えない" do
      Tenancy.with_tenant(supplier.id) do
        FactoryBot.create(:billable_item, unit_price: 120, quantity: 3, tax_rate_percent: 10)
        FactoryBot.create(:billable_item, unit_price: 99, quantity: 2, tax_rate_percent: 8)
        draft = FactoryBot.create(:invoice)
        FactoryBot.create(:billable_item, unit_price: 1_000, quantity: 1, invoice: draft, customer_tenant_id: draft.customer_tenant_id)
      end

      expect(unbilled_total).to eq(120 * 3 + 99 * 2).and be_an(Integer)
    end

    it "未請求の明細が無ければ 0 を返し、他社の明細を数えない" do
      expect(unbilled_total).to eq(0)

      Tenancy.with_tenant(other.id) { FactoryBot.create(:billable_item, unit_price: 500, quantity: 2) }
      Tenancy.with_tenant(supplier.id) { FactoryBot.create(:billable_item, unit_price: 7, quantity: 1) }

      # 対照：自社の未請求の明細は数える
      expect(unbilled_total).to eq(7)
    end
  end
end
