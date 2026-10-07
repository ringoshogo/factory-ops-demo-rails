require "rails_helper"

# 型の show? は scope と同じ条件で判定する（docs/architecture/graphql-schema.md「認可」）
RSpec.describe Sales::ItemPolicy do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:buyer_actor) do
    Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "")
  end
  let(:catalog_item) do
    Sales::PublishedCatalog::Item.new(supplier_tenant_id: supplier.id, code: "A-1", name: "n", unit: "個", unit_price: 1,
      tax_rate_percent: 10)
  end

  def show_to_buyer?(permissions:, traits: [])
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:partnership, *traits, buyer_tenant_id: buyer.id, permissions:)
    end
    Tenancy.with_tenant(buyer.id) { described_class.new(catalog_item, user: buyer_actor).apply(:show_to_buyer?) }
  end

  # RLS も同じ行を閉じるので、条件を落としても結果だけでは気付けない。条件そのものを確かめる
  describe "scope は所有と公開の条件を明示し、RLS に任せない" do
    def conditions(actor, name, **options)
      described_class.new(user: actor).apply_scope(Sales::Item.all, type: :active_record_relation, name:,
        scope_options: options.presence).where_values_hash
    end

    it "自社の品目は、所有テナントで絞る" do
      expect(Tenancy.with_tenant(buyer.id) { conditions(buyer_actor, :own) }).to eq("owner_tenant_id" => buyer.id)
    end

    it "経路 1 は、受注側テナントと公開で絞る" do
      Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[view_catalog]) }

      expect(Tenancy.with_tenant(buyer.id) { conditions(buyer_actor, :published_catalog, supplier_tenant_id: supplier.id) })
        .to eq("owner_tenant_id" => supplier.id, "published" => true)
    end
  end

  describe "show_to_buyer?" do
    it "有効な取引関係と view_catalog の付与があれば真" do
      expect(show_to_buyer?(permissions: %w[view_catalog])).to be(true)
    end

    it "view_catalog の付与が無ければ偽" do
      expect(show_to_buyer?(permissions: %w[place_orders view_shipments])).to be(false)
    end

    it "付与があっても、取引関係が失効していれば偽" do
      expect(show_to_buyer?(permissions: %w[view_catalog], traits: [ :revoked ])).to be(false)
    end
  end
end
