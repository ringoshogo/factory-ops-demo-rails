require "rails_helper"

# 請求対象明細。受注が検収した明細を未請求の明細として書き（docs/architecture/context-map.md「検収と請求の流れ」3）、
# ダッシュボードの未請求の合計は単価 × 検収数量を税抜きで合計する（docs/architecture/graphql-schema.md「読み取りの一覧」）
RSpec.describe Billing::BillableItems do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  def unbilled_total = Tenancy.with_tenant(supplier.id) { described_class.unbilled_total(actor) }

  describe ".confirm" do
    let(:shipment_id) { SecureRandom.uuid }
    let(:sales_order_line_id) { SecureRandom.uuid }
    let(:customer) { FactoryBot.create(:tenant) }
    let(:source_purchase_order_line_id) { SecureRandom.uuid }

    def confirm(**overrides)
      described_class.confirm(customer_tenant_id: customer.id, shipment_id:, sales_order_line_id:, source_purchase_order_line_id:,
        item_name: "六角ボルト M8", unit_price: 120, quantity: 3, tax_rate_percent: 8, inspected_on: Date.new(2026, 10, 21), **overrides)
    end

    def items
      Tenancy.with_tenant(supplier.id) do
        Billing::BillableItem.where(owner_tenant_id: supplier.id).order(:id).map do |item|
          item.attributes.symbolize_keys.slice(:owner_tenant_id, :customer_tenant_id, :shipment_id, :sales_order_line_id,
            :source_purchase_order_line_id, :item_name, :unit_price, :quantity, :tax_rate_percent, :inspected_on, :invoice_id)
        end
      end
    end

    it "いまのテナントの名義で、取引先を得意先にした未請求の明細を書き、値を返さない" do
      expect(Tenancy.with_tenant(supplier.id) { confirm }).to be_nil

      expect(items).to eq([ { owner_tenant_id: supplier.id, customer_tenant_id: customer.id, shipment_id:, sales_order_line_id:,
        source_purchase_order_line_id:, item_name: "六角ボルト M8", unit_price: 120, quantity: 3, tax_rate_percent: 8,
        inspected_on: Date.new(2026, 10, 21), invoice_id: nil } ])
    end

    it "同じ出荷実績と受注明細の組で 2 回呼んでも 1 行で、別の受注明細は別の行にする" do
      Tenancy.with_tenant(supplier.id) { 2.times { confirm } }
      expect(items.size).to eq(1)

      Tenancy.with_tenant(supplier.id) { confirm(sales_order_line_id: SecureRandom.uuid) }
      expect(items.size).to eq(2)
    end

    it "請求済みの明細と同じ組で呼んでも、未請求の明細を作り直さない" do
      Tenancy.with_tenant(supplier.id) { confirm }
      # 確定した請求書には明細を結べないので、下書きに結んでから確定する
      invoice = Tenancy.with_tenant(supplier.id) do
        FactoryBot.create(:invoice, customer_tenant_id: customer.id).tap do |invoice|
          Billing::BillableItem.update_all(invoice_id: invoice.id)
          invoice.update!(issued_at: Time.current, invoice_number: "INV-#{SecureRandom.hex(4)}")
        end
      end

      Tenancy.with_tenant(supplier.id) { confirm }

      expect(items.map { _1[:invoice_id] }).to eq([ invoice.id ])
    end

    # 冪等キーの一意索引はテナントをまたぐので、他社の同じ組の行があれば書かない。他社の行は書き換えない
    it "他社に同じ出荷実績と受注明細の組の行があれば、自社の行を書かない" do
      Tenancy.with_tenant(other.id) { FactoryBot.create(:billable_item, shipment_id:, sales_order_line_id:) }
      # 対照：別の組なら自社の行を書く
      Tenancy.with_tenant(supplier.id) { confirm(shipment_id: SecureRandom.uuid) }
      expect(items.size).to eq(1)

      Tenancy.with_tenant(supplier.id) { confirm }

      expect(items.map { _1[:shipment_id] }).not_to include(shipment_id)
      expect(Tenancy.with_tenant(other.id) { Billing::BillableItem.where(shipment_id:).pluck(:owner_tenant_id) }).to eq([ other.id ])
    end

    it "テナントの設定の外では、何も書かずに例外にする" do
      expect { confirm }.to raise_error(Tenancy::MissingTenant)
      expect(items).to be_empty
    end
  end

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
