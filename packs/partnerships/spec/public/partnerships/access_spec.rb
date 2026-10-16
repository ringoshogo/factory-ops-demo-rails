require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

# 取引関係の公開 API の判定と可視範囲（docs/architecture/data-model.md「取引関係と権限付与（`partnerships`）」）
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

  # 経路 3 の出荷の scope と規則が使う、権限を与えている受注側。ID の集合と、副問い合わせを SqlSubquery#contains で結んだ絞り込みの
  # 両方が同じ集合を返すことを確かめる
  describe "Access.permitting_supplier_ids と permitting_suppliers_sql" do
    def ids(actor = buyer_actor, permission: "view_shipments")
      Tenancy.with_tenant(actor.tenant_id) { Partnerships::Access.permitting_supplier_ids(actor, permission:) }
    end

    # 副問い合わせで絞ったテナントの ID。結ぶ側は役割の名前（tenant_id）だけを書く
    def contained(actor = buyer_actor, permission: "view_shipments")
      Tenancy.with_tenant(actor.tenant_id) do
        suppliers = Partnerships::Access.permitting_suppliers_sql(actor, permission:)
        Partnerships::Tenant.where(suppliers.contains(:tenant_id, Partnerships::Tenant.arel_table[:id])).pluck(:id).to_set
      end
    end

    it "有効な関係と付与のある受注側だけを返し、失効した関係と付与の無い関係の受注側を返さない" do
      partnership(permissions: %w[view_shipments])
      revoked = FactoryBot.create(:tenant)
      Tenancy.with_tenant(revoked.id) { FactoryBot.create(:partnership, :revoked, buyer_tenant_id: buyer.id, permissions: %w[view_shipments]) }
      ungranted = FactoryBot.create(:tenant)
      Tenancy.with_tenant(ungranted.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[view_catalog]) }

      expect(ids).to eq(Set[supplier.id])
      expect(ids).to be_frozen
      expect(contained).to eq(Set[supplier.id])
      # 対照：付与のある権限を問えば、付与の無い関係の受注側も返る
      expect(ids(permission: "view_catalog")).to eq(Set[ungranted.id])
      expect(contained(permission: "view_catalog")).to eq(Set[ungranted.id])
    end

    it "知らない権限は、どちらも例外" do
      expect { ids(permission: "delete_everything") }.to raise_error(ArgumentError)
      expect { contained(permission: "delete_everything") }.to raise_error(ArgumentError)
    end

    # RLS は自社が発注側でない関係を隠すので、scope を外しても上の example は落ちない。RLS の SELECT と UPDATE を開いて確かめる
    # （docs/guides/testing.md「行列テストとの分担」）
    describe "RLS の SELECT と UPDATE を開いたとき" do
      include_context "RLS の SELECT と UPDATE を開く"

      it "他社が発注側の関係の受注側を、ID の集合も副問い合わせの絞り込みも返さない" do
        partnership(permissions: %w[view_shipments])
        other_supplier = FactoryBot.create(:tenant)
        theirs = Tenancy.with_tenant(other_supplier.id) do
          FactoryBot.create(:partnership, buyer_tenant_id: FactoryBot.create(:tenant).id, permissions: %w[view_shipments])
        end

        Tenancy.with_tenant(buyer.id) do
          cross_read!
          # 対照：開いた後は、他社が発注側の関係が見える
          expect(Partnerships::Partnership.where(id: theirs.id)).to exist
          expect(Partnerships::Access.permitting_supplier_ids(buyer_actor, permission: "view_shipments")).to eq(Set[supplier.id])
          suppliers = Partnerships::Access.permitting_suppliers_sql(buyer_actor, permission: "view_shipments")
          expect(Partnerships::Tenant.where(suppliers.contains(:tenant_id, Partnerships::Tenant.arel_table[:id])).pluck(:id))
            .to eq([ supplier.id ])
        end
      end
    end
  end

  describe "Directory" do
    it "user_names は自社のユーザーの名前だけを返す" do
      own = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, name: "受注の担当") }
      other = Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) }

      names = Tenancy.with_tenant(supplier.id) { Partnerships::Directory.user_names(supplier_actor, [ own.id, other.id ]) }
      expect(names).to eq(own.id => "受注の担当")
    end

    # 一覧のテストの規則で、関係を 2 件作る（docs/architecture/graphql-schema.md「ページングと N+1」）
    it "for_buyer は有効な関係だけを、相手と付与ごとに返し、失効すると返さない" do
      record = partnership(permissions: %w[view_shipments view_catalog])
      other = FactoryBot.create(:tenant)
      Tenancy.with_tenant(other.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders]) }

      buyer_view = Tenancy.with_tenant(buyer.id) { Partnerships::Directory.for_buyer(buyer_actor) }
      expect(buyer_view.map { [ _1.supplier.name, _1.permissions ] })
        .to contain_exactly([ supplier.name, %w[view_catalog view_shipments] ], [ other.name, %w[place_orders] ])

      Tenancy.with_tenant(supplier.id) { Partnerships::Management.revoke(supplier_actor, partnership_id: record.id) }

      expect(Tenancy.with_tenant(buyer.id) { Partnerships::Directory.for_buyer(buyer_actor) }.map { _1.supplier.name })
        .to eq([ other.name ])
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
