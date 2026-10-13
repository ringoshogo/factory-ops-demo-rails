require "rails_helper"

# テナントの名前の副問い合わせ。受注・購買・出荷の一覧が、伝票の相手のテナント ID で結んで名前で並べる
# （docs/adr/010-状況の導出をSQLの式1つにする.md）
RSpec.describe Partnerships::Directory, ".tenant_names_sql" do
  let!(:supplier) { FactoryBot.create(:tenant, name: "青嵐精機工業") }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  it "列は ID と名前だけで、取引用コードを含まない" do
    names = described_class.tenant_names_sql(actor)

    expect(names.columns).to eq(tenant_id: "id", name: "name")
    expect(ActiveRecord::Base.lease_connection.select_all(names.sql).columns).to eq(%w[id name])
  end

  it "結ぶ側の行ごとに、相手のテナントの名前を 1 つ引き、結ぶ側の行を増やさない" do
    buyers = %w[組立メーカー 部品商社].map { FactoryBot.create(:tenant, name: _1) }
    names = described_class.tenant_names_sql(actor)
    partnerships = Partnerships::Partnership.arel_table

    rows = Tenancy.with_tenant(supplier.id) do
      buyers.each { FactoryBot.create(:partnership, buyer_tenant_id: _1.id) }
      Partnerships::Partnership.order(:id).pluck(names.lookup(:name, :tenant_id, partnerships[:buyer_tenant_id]))
    end

    # 対照：テナントの表には結ぶ相手のほかの行もある
    expect(Partnerships::Tenant.count).to be > buyers.size
    expect(rows).to eq(%w[組立メーカー 部品商社])
  end

  it "取引関係の操作者でなければ引数の誤りにする" do
    expect { described_class.tenant_names_sql(nil) }.to raise_error(ArgumentError)
  end
end
