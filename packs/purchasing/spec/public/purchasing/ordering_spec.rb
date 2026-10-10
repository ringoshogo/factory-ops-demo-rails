require "rails_helper"

# 発注の登録。発注できない相手は理由を区別せず NOT_PERMITTED にし、明細の誤りは項目を指す INVALID_INPUT にする。
# どちらの失敗も、発注も「発注登録」も残さない（docs/architecture/context-map.md「発注の連結と品番の照合」1、「取引関係の失効」）
RSpec.describe Purchasing::Ordering do
  let!(:buyer) { FactoryBot.create(:tenant) }
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:partnership) do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders]) }
  end

  def actor_of(tenant, role: "member")
    Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role:, partner_code: "")
  end

  def place(supplier_tenant_id: supplier.id, lines: [ { part_number: "MY-BOLT", quantity: 10 } ], tenant: buyer, **options)
    Tenancy.with_tenant(tenant.id) { described_class.place(actor_of(tenant), supplier_tenant_id:, lines:, **options) }
  end

  def purchase_order_count = Tenancy.with_tenant(buyer.id) { Purchasing::PurchaseOrder.count }

  def supplier_with_partnership(*traits, **options)
    FactoryBot.create(:tenant).tap do |other|
      Tenancy.with_tenant(other.id) { FactoryBot.create(:partnership, *traits, buyer_tenant_id: buyer.id, **options) }
    end
  end

  let(:published) { [] }

  before { allow(Contracts).to receive(:publish).and_wrap_original { |original, event| published << event; original.call(event) } }

  it "発注と明細を書き、同じ明細の「発注登録」を出す" do
    result = place(lines: [ { part_number: "MY-BOLT", quantity: 10 }, { part_number: "MY-NUT", quantity: 3 } ], desired_delivery_on: Date.new(2026, 11, 2))

    expect(result).to be_success
    expect(result.value).to have_attributes(supplier_tenant_id: supplier.id, status: :sent, desired_delivery_on: Date.new(2026, 11, 2))
    expect(published.sole).to have_attributes(class: Contracts::PurchaseOrderPlaced, purchase_order_id: result.value.id,
      buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id, desired_delivery_on: "2026-11-02")
    expect(published.sole.lines.map { _1.slice("part_number", "quantity") })
      .to eq([ { "part_number" => "MY-BOLT", "quantity" => 10 }, { "part_number" => "MY-NUT", "quantity" => 3 } ])
  end

  describe "発注できない相手" do
    # 結果がまったく同じなので、相手テナントが存在するかどうかも、関係の有無も推測できない
    it "存在しない・関係の無い・失効した・付与の無い・撤回した相手と自分自身が、どれも同じ NOT_PERMITTED になり、何も残らない" do
      withdrawn = FactoryBot.create(:tenant).tap do |other|
        Tenancy.with_tenant(other.id) do
          granted = FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders])
          Partnerships::Management.withdraw(actor_of(other, role: "admin"), partnership_id: granted.id, permission: "place_orders")
        end
      end
      targets = {
        "存在しない" => SecureRandom.uuid,
        "関係の無い" => FactoryBot.create(:tenant).id,
        "失効した" => supplier_with_partnership(:revoked, permissions: %w[view_catalog place_orders view_shipments]).id,
        "付与の無い" => supplier_with_partnership(permissions: %w[view_catalog view_shipments]).id,
        "撤回した" => withdrawn.id,
        "自分自身" => buyer.id
      }

      targets.each do |label, supplier_tenant_id|
        expect(place(supplier_tenant_id:).failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_permitted, [ :supplier_tenant_id ] ] ]), label
      end
      expect(purchase_order_count).to eq(0)
      expect(published).to be_empty
    end

    it "取引関係を失効させると、新しい発注は NOT_PERMITTED になる" do
      expect(place).to be_success

      Tenancy.with_tenant(supplier.id) { Partnerships::Management.revoke(actor_of(supplier, role: "admin"), partnership_id: partnership.id) }

      expect(place.failures.map(&:code)).to eq([ :not_permitted ])
    end
  end

  describe "明細の誤り" do
    def failure_of(lines) = place(lines:).failures.sole.deconstruct

    it "誤りのある最初の項目を INVALID_INPUT で指し、発注も「発注登録」も残さない" do
      expect(failure_of([])).to eq([ :invalid_input, [ :lines ], "Lines can't be empty" ])
      expect(failure_of([ { part_number: "A", quantity: 0 } ])).to eq([ :invalid_input, [ :lines, 0, :quantity ], "Quantity must be positive" ])
      expect(failure_of([ { part_number: "", quantity: 1 } ]).first(2)).to eq([ :invalid_input, [ :lines, 0, :part_number ] ])
      expect(failure_of([ { part_number: "A", quantity: 1 }, { part_number: "A", quantity: 2 } ]).first(2))
        .to eq([ :invalid_input, [ :lines, 1, :part_number ] ])
      expect(purchase_order_count).to eq(0)
      expect(published).to be_empty
    end

    it "明細の数と品番の長さの上限を超えると INVALID_INPUT になり、上限ちょうどは通る" do
      lines = ->(count) { Array.new(count) { { part_number: "P-#{_1}", quantity: 1 } } }

      expect(failure_of(lines.(101))).to eq([ :invalid_input, [ :lines ], "Lines must be at most 100" ])
      expect(failure_of([ { part_number: "A" * 65, quantity: 1 } ]))
        .to eq([ :invalid_input, [ :lines, 0, :part_number ], "Part number must be at most 64 characters" ])
      expect(purchase_order_count).to eq(0)

      expect(place(lines: lines.(100))).to be_success
      expect(place(lines: [ { part_number: "A" * 64, quantity: 1 } ])).to be_success
    end
  end

  it "伝票番号は発注側のテナントごとに続き番号になる" do
    other_buyer = FactoryBot.create(:tenant)
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: other_buyer.id, permissions: %w[place_orders]) }

    expect([ place, place, place(tenant: other_buyer) ].map { _1.value.order_no }).to eq(%w[PO-000001 PO-000002 PO-000001])
  end
end
