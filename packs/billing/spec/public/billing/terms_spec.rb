require "rails_helper"

# 請求条件。取引先は自社が受注側の取引関係（失効したものを含む）の相手に限り、締め日は 1〜28 と月末の 31 だけを許す
# （docs/architecture/data-model.md「請求（`billing`）」）
RSpec.describe Billing::Terms do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:customers) { FactoryBot.create_list(:tenant, 2) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  before do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:partnership, buyer_tenant_id: customers[0].id)
      FactoryBot.create(:partnership, :revoked, buyer_tenant_id: customers[1].id)
    end
  end

  def set(customer_tenant_id: customers[0].id, closing_day: 20)
    Tenancy.with_tenant(supplier.id) { described_class.set(actor, customer_tenant_id:, closing_day:) }
  end

  def terms = Tenancy.with_tenant(supplier.id) { Billing::BillingTerm.order(:customer_tenant_id).pluck(:customer_tenant_id, :closing_day) }

  def failure_of(result) = result.failures.map { [ _1.code, _1.path ] }

  describe ".set" do
    it "取引先の請求条件を作り、2 回目は締め日を変える。失効した取引関係の相手にも作れる" do
      expect(set.value).to have_attributes(customer_tenant_id: customers[0].id, closing_day: 20, owner_tenant_id: supplier.id)
      expect(set(closing_day: 31)).to be_success
      expect(set(customer_tenant_id: customers[1].id, closing_day: 1)).to be_success

      expect(terms).to match_array([ [ customers[0].id, 31 ], [ customers[1].id, 1 ] ])
    end

    [ 1, 28, 31 ].each do |day|
      it "締め日 #{day} を受け付ける" do
        expect(set(closing_day: day)).to be_success
      end
    end

    [ 0, 29, 30, 32 ].each do |day|
      it "締め日 #{day} は INVALID_INPUT で、条件を書かない" do
        expect(failure_of(set(closing_day: day))).to eq([ [ :invalid_input, [ :closing_day ] ] ])
        expect(terms).to be_empty
      end
    end

    it "自社が受注側の取引関係の相手でないテナントと、存在しないテナントは NOT_FOUND" do
      [ FactoryBot.create(:tenant).id, SecureRandom.uuid, supplier.id ].each do |id|
        expect(failure_of(set(customer_tenant_id: id))).to eq([ [ :not_found, [ :customer_tenant_id ] ] ])
      end
      expect(terms).to be_empty
    end

    it "取引先の誤りは、締め日の誤りより先に NOT_FOUND になる" do
      expect(failure_of(set(customer_tenant_id: SecureRandom.uuid, closing_day: 0))).to eq([ [ :not_found, [ :customer_tenant_id ] ] ])
    end
  end

  describe ".list" do
    it "自社の請求条件だけを返す" do
      set
      set(customer_tenant_id: customers[1].id, closing_day: 31)
      Tenancy.with_tenant(customers[0].id) { FactoryBot.create(:billing_term) }

      expect(Tenancy.with_tenant(supplier.id) { described_class.list(actor) }.map { [ _1.customer_tenant_id, _1.closing_day ] })
        .to match_array([ [ customers[0].id, 20 ], [ customers[1].id, 31 ] ])
    end
  end
end
