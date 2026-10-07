require "rails_helper"

# 取引関係を結ぶ・失効させる・権限を付与する操作と、表の制約（docs/architecture/data-model.md「取引関係と権限付与」）
RSpec.describe "Partnerships::Management" do
  # with_tenant の中で初めて作ると、例外で戻したセーブポイントと一緒に消える
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) do
    Partnerships::Actor.new(user_id: SecureRandom.uuid, tenant_id: supplier.id, name: "name", email: "e@example.com",
      role: "admin", partner_code: supplier.partner_code)
  end

  def as_supplier(&) = Tenancy.with_tenant(supplier.id, &)

  def establish(partner_code = buyer.partner_code)
    as_supplier { Partnerships::Management.establish(actor, partner_code:) }
  end

  def failure_codes(result) = result.failures.map(&:code)

  describe "establish" do
    it "取引用コードで相手を指定して、有効な関係を結ぶ" do
      result = establish

      expect(result).to be_success
      expect(result.value).to have_attributes(status: "active", buyer: Partnerships::TenantSummary.new(id: buyer.id, name: buyer.name))
    end

    it "存在しない取引用コードと、テナントの code の指定は、どちらも NOT_FOUND" do
      expect(failure_codes(establish("no-such-code"))).to eq([ :not_found ])
      expect(failure_codes(establish(buyer.code))).to eq([ :not_found ])
    end

    it "自社の取引用コードは INVALID_INPUT" do
      expect(failure_codes(establish(supplier.partner_code))).to eq([ :invalid_input ])
    end

    it "有効な関係がある相手とは CONFLICT になり、リクエストのトランザクションは使い続けられる" do
      establish

      as_supplier do
        expect(failure_codes(Partnerships::Management.establish(actor, partner_code: buyer.partner_code))).to eq([ :conflict ])
        expect(Partnerships::Partnership.count).to eq(1)
      end
    end

    it "失効させた後は、新しい関係を結べる。失効した関係は失効のまま残る" do
      first = establish.value
      as_supplier { Partnerships::Management.revoke(actor, partnership_id: first.id) }

      second = establish.value

      expect(second.id).not_to eq(first.id)
      expect(as_supplier { Partnerships::Directory.for_supplier(actor) }.to_h { [ _1.id, _1.status ] })
        .to eq(first.id => "revoked", second.id => "active")
    end
  end

  describe "revoke・grant・withdraw" do
    let!(:partnership) { establish.value }

    it "権限の付与と撤回は、繰り返しても結果が変わらない" do
      2.times { as_supplier { Partnerships::Management.grant(actor, partnership_id: partnership.id, permission: "place_orders") } }
      expect(as_supplier { Partnerships::Directory.partnership(actor, partnership.id) }.permissions).to eq(%w[place_orders])

      2.times { as_supplier { Partnerships::Management.withdraw(actor, partnership_id: partnership.id, permission: "place_orders") } }
      expect(as_supplier { Partnerships::Directory.partnership(actor, partnership.id) }.permissions).to be_empty
    end

    it "失効させた関係は、失効し直すことも、権限を変えることもできない（CONFLICT）" do
      result = as_supplier { Partnerships::Management.revoke(actor, partnership_id: partnership.id) }
      expect(result.value).to have_attributes(status: "revoked", revoked_at: be_present)

      as_supplier do
        expect(failure_codes(Partnerships::Management.revoke(actor, partnership_id: partnership.id))).to eq([ :conflict ])
        expect(failure_codes(Partnerships::Management.grant(actor, partnership_id: partnership.id, permission: "view_catalog")))
          .to eq([ :conflict ])
      end
    end

    it "自社が受注側でない関係は NOT_FOUND" do
      buyer_actor = actor.with(tenant_id: buyer.id)

      Tenancy.with_tenant(buyer.id) do
        expect(failure_codes(Partnerships::Management.revoke(buyer_actor, partnership_id: partnership.id))).to eq([ :not_found ])
      end
    end
  end

  describe "表の制約" do
    def insert(**attributes)
      as_supplier { Partnerships::Partnership.create!(owner_tenant_id: supplier.id, buyer_tenant_id: buyer.id, **attributes) }
    end

    it "自分自身との関係は不可" do
      expect { insert(buyer_tenant_id: supplier.id) }.to raise_error(ActiveRecord::StatementInvalid, /partnerships_not_self/)
    end

    it "status と revoked_at は一致する" do
      expect { insert(status: "revoked") }.to raise_error(ActiveRecord::StatementInvalid, /partnerships_status_revoked_at/)
      expect { insert(revoked_at: Time.current) }.to raise_error(ActiveRecord::StatementInvalid, /partnerships_status_revoked_at/)
    end

    it "権限付与は、取引関係と同じ所有テナントでなければならない" do
      partnership = insert
      other = FactoryBot.create(:tenant)

      expect {
        Tenancy.with_tenant(other.id) do
          # 相手の関係は RLS で見えないので、belongs_to の検証を飛ばして DB の複合外部キーに当てる
          Partnerships::PartnershipGrant.new(owner_tenant_id: other.id, partnership_id: partnership.id, permission: "view_catalog")
            .save!(validate: false)
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end
end
