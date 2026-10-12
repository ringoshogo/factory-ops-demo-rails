require "rails_helper"

# ダッシュボードの安全在庫。有効在庫（現在庫 - 引当）が安全在庫より小さい在庫だけを返し、等しい在庫は返さない
# （docs/architecture/data-model.md「在庫（`inventory`）」、docs/architecture/graphql-schema.md「読み取りの一覧」）
RSpec.describe Inventory::Stocks do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  def below_safety_stock = Tenancy.with_tenant(supplier.id) { described_class.below_safety_stock(actor) }

  describe ".below_safety_stock" do
    it "有効在庫が安全在庫より 1 小さい在庫を返し、等しい在庫と大きい在庫を返さない。引当を差し引いて比べる" do
      below, equal, above, allocated_below = Tenancy.with_tenant(supplier.id) do
        [ FactoryBot.create(:stock, on_hand: 4, safety_stock: 5),
          FactoryBot.create(:stock, on_hand: 5, safety_stock: 5),
          FactoryBot.create(:stock, on_hand: 6, safety_stock: 5),
          FactoryBot.create(:stock, on_hand: 10, allocated: 6, safety_stock: 5) ]
      end

      expect(below_safety_stock.map(&:item_id)).to match_array([ below.item_id, allocated_below.item_id ])
      expect(below_safety_stock).to all(have_attributes(below_safety_stock: true))
      expect([ equal, above ].map(&:item_id) & below_safety_stock.map(&:item_id)).to be_empty
    end

    it "他社の在庫を返さない" do
      own = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:stock, on_hand: 0, safety_stock: 1) }
      Tenancy.with_tenant(other.id) { FactoryBot.create(:stock, on_hand: 0, safety_stock: 1) }

      # 対照：同じ条件の自社の在庫は返る
      expect(below_safety_stock.map(&:item_id)).to eq([ own.item_id ])
    end
  end
end
