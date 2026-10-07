require "rails_helper"

# 取引関係の公開 API の判定と可視範囲（docs/architecture/data-model.md「取引関係と権限付与」）
RSpec.describe "Partnerships::Access と Directory" do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:supplier_actor) { actor_of(supplier) }
  let(:buyer_actor) { actor_of(buyer) }

  def actor_of(tenant, role: "admin")
    Partnerships::Actor.new(user_id: SecureRandom.uuid, tenant_id: tenant.id, name: "name", email: "e@example.com", role:,
      partner_code: tenant.partner_code)
  end

  def partnership(*traits, permissions: [])
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:partnership, *traits, buyer_tenant_id: buyer.id, permissions:)
    end
  end

  def permitted?(actor = buyer_actor, supplier_tenant_id: supplier.id, permission: "view_catalog")
    Tenancy.with_tenant(actor.tenant_id) { Partnerships::Access.permitted?(actor, supplier_tenant_id:, permission:) }
  end

  describe "Access.permitted?" do
    it "有効な取引関係と、その権限の付与があれば真" do
      partnership(permissions: %w[view_catalog])

      expect(permitted?).to be(true)
      expect(permitted?(permission: "place_orders")).to be(false)
    end

    it "権限の付与が無ければ偽" do
      partnership

      expect(permitted?).to be(false)
    end

    it "失効した取引関係では、付与があっても偽" do
      partnership(:revoked, permissions: %w[view_catalog])

      expect(permitted?).to be(false)
    end

    it "関係の無いテナント・存在しないテナント・ID でない値は、どれも同じく偽" do
      partnership(permissions: %w[view_catalog])

      expect(permitted?(actor_of(FactoryBot.create(:tenant)))).to be(false)
      expect(permitted?(supplier_tenant_id: SecureRandom.uuid)).to be(false)
      expect(permitted?(supplier_tenant_id: "not-a-uuid")).to be(false)
    end

    it "受注側から見て逆向きの関係は判定に使わない" do
      partnership(permissions: %w[view_catalog])

      expect(permitted?(supplier_actor, supplier_tenant_id: buyer.id)).to be(false)
    end

    it "知らない権限は例外" do
      expect { permitted?(permission: "delete_everything") }.to raise_error(ArgumentError)
    end
  end

  describe "Directory" do
    it "for_buyer は有効な関係だけを返し、失効すると空になる" do
      record = partnership(permissions: %w[view_shipments view_catalog])

      buyer_view = Tenancy.with_tenant(buyer.id) { Partnerships::Directory.for_buyer(buyer_actor) }
      expect(buyer_view.map { [ _1.supplier.name, _1.permissions ] }).to eq([ [ supplier.name, %w[view_catalog view_shipments] ] ])

      Tenancy.with_tenant(supplier.id) { Partnerships::Management.revoke(supplier_actor, partnership_id: record.id) }

      expect(Tenancy.with_tenant(buyer.id) { Partnerships::Directory.for_buyer(buyer_actor) }).to be_empty
    end

    # RLS は経路 2 で相手の行も返すので、scope が所有の条件を明示していなければ、ここに相手の関係が混ざる
    it "for_supplier と partnership は、RLS で見える相手の関係を自社の関係として返さない" do
      record = partnership

      Tenancy.with_tenant(buyer.id) do
        expect(Partnerships::Partnership.where(id: record.id)).to exist
        expect(Partnerships::Directory.for_supplier(buyer_actor)).to be_empty
        expect(Partnerships::Directory.partnership(buyer_actor, record.id)).to be_nil
      end
    end

    it "for_supplier は失効した関係も返す" do
      partnership(:revoked)

      result = Tenancy.with_tenant(supplier.id) { Partnerships::Directory.for_supplier(supplier_actor) }
      expect(result.map(&:status)).to eq(%w[revoked])
    end

    it "操作者の無い呼び出しは例外" do
      expect { Tenancy.with_tenant(supplier.id) { Partnerships::Directory.for_supplier(nil) } }.to raise_error(ArgumentError)
    end
  end

  # RLS も失効した関係を閉じるので、上の振る舞いのテストは scope の条件が抜けても通る。scope の条件そのものを確かめる
  describe "PartnershipPolicy" do
    it "as_buyer の scope は RLS に頼らず、自社が発注側の有効な関係に絞る" do
      relation = Tenancy.with_tenant(buyer.id) { Partnerships::Scope.call(buyer_actor, :as_buyer) }

      expect(relation.where_values_hash).to eq("status" => "active", "buyer_tenant_id" => buyer.id)
    end

    it "as_supplier の scope は自社が受注側の関係に絞る" do
      relation = Tenancy.with_tenant(supplier.id) { Partnerships::Scope.call(supplier_actor, :as_supplier) }

      expect(relation.where_values_hash).to eq("owner_tenant_id" => supplier.id)
    end

    it "発注側の型の規則は、失効した関係を拒否する" do
      value = Partnerships::PartnershipValue.new(id: SecureRandom.uuid, supplier: supplier, buyer: buyer, status: "revoked",
        revoked_at: Time.current, permissions: [])
      policy = Partnerships::PartnershipPolicy.new(value, user: buyer_actor)

      expect(policy.apply(:show_to_buyer?)).to be(false)
      expect(Partnerships::PartnershipPolicy.new(value.with(status: "active", revoked_at: nil), user: buyer_actor).apply(:show_to_buyer?))
        .to be(true)
    end

    it "取引関係を変える規則は、自社が受注側の関係の admin にだけ真" do
      value = Partnerships::PartnershipValue.new(id: SecureRandom.uuid, supplier: supplier, buyer: buyer, status: "active",
        revoked_at: nil, permissions: [])

      expect(Partnerships::PartnershipPolicy.new(value, user: supplier_actor).apply(:manage?)).to be(true)
      expect(Partnerships::PartnershipPolicy.new(value, user: actor_of(supplier, role: "member")).apply(:manage?)).to be(false)
      expect(Partnerships::PartnershipPolicy.new(value, user: buyer_actor).apply(:manage?)).to be(false)
    end
  end
end
