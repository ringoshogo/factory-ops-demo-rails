require "rails_helper"

# 取り込みの品目の書き込み（docs/architecture/data-model.md「取り込み（`imports`）」）。品目の列だけを品目コードで upsert し、
# 新しい品目には最初の単価を有効期間 (,) の行で足す。既存の品目の単価には触れない（単価の改定は Sales::ItemPrices だけが行う）
RSpec.describe Sales::Catalog, ".bulk_upsert" do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:other) { FactoryBot.create(:tenant) }
  let(:actor) do
    Partnerships::Actor.new(user_id: SecureRandom.uuid, tenant_id: supplier.id, name: "", email: "", role: "admin", partner_code: "")
  end

  # 他社の行を作る example があるので、テナントは example の中で開く
  def mine(&) = Tenancy.with_tenant(supplier.id, &)

  def row(code, unit_price: 300, name: "取り込んだ品目", published: false)
    { code:, name:, unit: "個", tax_rate_percent: 10, published:, unit_price: }
  end

  def prices(item_id) = Sales::ItemPrice.where(item_id:).order(:recorded_period).pluck(:unit_price, :valid_period, :recorded_by_user_id)

  it "新しいコードは品目と有効期間 (,) の単価の行を作り、既存のコードは品目の列だけを書き換えて単価に触れない" do
    mine do
      existing = FactoryBot.create(:item, code: "OLD-1", name: "旧名", unit_price: 120)

      results = described_class.bulk_upsert(actor, [ row("NEW-1"), row("OLD-1", unit_price: 999, name: "新名", published: true) ])

      expect(results.transform_values { _1.value.created }).to eq("NEW-1" => true, "OLD-1" => false)
      expect(results["OLD-1"].value.item_id).to eq(existing.id)
      created = described_class.item(actor, results["NEW-1"].value.item_id)
      expect(created).to have_attributes(code: "NEW-1", name: "取り込んだ品目", unit_price: 300, published: false)
      expect(prices(created.id)).to eq([ [ 300, -Float::INFINITY...Float::INFINITY, actor.user_id ] ])
      expect(described_class.item(actor, existing.id)).to have_attributes(name: "新名", published: true, unit_price: 120)
      expect(prices(existing.id).map(&:first)).to eq([ 120 ])
    end
  end

  it "単価の空の新しい品目は書かずに単価を指す INVALID_INPUT にし、単価の空の既存の品目は品目の列だけを書く" do
    mine do
      FactoryBot.create(:item, code: "OLD-1", name: "旧名")

      results = described_class.bulk_upsert(actor, [ row("NEW-1", unit_price: nil), row("OLD-1", unit_price: nil, name: "新名") ])

      expect(results["NEW-1"].failures.map { [ _1.code, _1.path ] }).to eq([ [ :invalid_input, [ :unit_price ] ] ])
      expect(results["OLD-1"]).to be_success
      expect(described_class.ids_by_codes(actor, %w[NEW-1 OLD-1]).keys).to eq(%w[OLD-1])
      expect(described_class.items(actor, first: 10, after: nil).values.map(&:name)).to eq(%w[新名])
    end
  end

  it "他社の同じコードの品目に触れず、自社の品目を作る" do
    theirs = Tenancy.with_tenant(other.id) { FactoryBot.create(:item, code: "SAME-1", name: "他社の品目") }

    expect(mine { described_class.bulk_upsert(actor, [ row("SAME-1") ])["SAME-1"].value.created }).to be(true)

    expect(Tenancy.with_tenant(other.id) { Sales::Item.find(theirs.id).name }).to eq("他社の品目")
    ids = mine { described_class.ids_by_codes(actor, %w[SAME-1]).values }
    expect(ids.size).to eq(1)
    expect(ids).not_to include(theirs.id)
  end

  # bulk_upsert は owner_tenant_id に Current.tenant_id を明示して入れる。他社の名義の行は、RLS の WITH CHECK が文ごと拒む
  it "upsert_all に他社の owner_tenant_id の行を混ぜると、RLS が拒んで 1 行も書かない" do
    now = Time.current
    rows = [ supplier, other ].map.with_index do |tenant, index|
      { owner_tenant_id: tenant.id, code: "MIX-#{index}", name: "混ぜた行", unit: "個", tax_rate_percent: 10, published: false,
        created_at: now, updated_at: now }
    end

    mine do
      expect { Sales::Item.transaction(requires_new: true) { Sales::Item.upsert_all(rows, unique_by: %i[owner_tenant_id code]) } }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
      expect(Sales::Item.where(code: %w[MIX-0 MIX-1])).to be_empty
      # 対照：自社の行だけなら書ける
      Sales::Item.upsert_all(rows.first(1), unique_by: %i[owner_tenant_id code])
      expect(Sales::Item.where(code: %w[MIX-0 MIX-1]).pluck(:code)).to eq(%w[MIX-0])
    end
  end

  it "ids_by_codes は、自社の品目だけをコードから引く" do
    own = mine { FactoryBot.create(:item, code: "C-1") }
    Tenancy.with_tenant(other.id) { FactoryBot.create(:item, code: "C-2") }

    expect(mine { described_class.ids_by_codes(actor, %w[C-1 C-2 C-3]) }).to eq("C-1" => own.id)
  end
end
