require "rails_helper"

# 単価の行の経路 1（docs/architecture/data-model.md「RLS」、docs/adr/006 決定 7）。品目が見える相手には、その品目の
# 現在の行だけが見え、閉じた行（訂正の前の値）と、見えない品目の行は見えない。行列の世界の公開品目は閉じた行を持たないので、
# 記録期間の条件はここで確かめる
RSpec.describe "item_prices の経路 1" do
  include ActiveSupport::Testing::TimeHelpers

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "admin", partner_code: "") }

  # 公開品目の行を 1 度訂正し、閉じた行と現在の行を 1 つずつ持たせる。非公開の品目も 1 つ持つ
  let!(:published) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:partnership, buyer_tenant_id: buyer.id)
      FactoryBot.create(:item_price, unit_price: 120)
      item = travel_to(1.day.ago) { FactoryBot.create(:item, :published, unit_price: 100) }
      row = Sales::ItemPrices.history(actor, [ item.id ]).fetch(item.id).sole
      Sales::ItemPrices.correct(actor, item_price_id: row.id, unit_price: 90, reason: "入力の誤り")
      item
    end
  end

  def visible_prices(tenant)
    Tenancy.with_tenant(tenant.id) do
      ActiveRecord::Base.lease_connection.select_rows("SELECT item_id, unit_price FROM item_prices ORDER BY unit_price")
    end
  end

  it "受注側には閉じた行も見え、取引関係のある発注側には公開品目の現在の行だけが見える" do
    expect(visible_prices(supplier).map(&:last)).to eq([ 90, 100, 120 ])
    expect(visible_prices(buyer)).to eq([ [ published.id, 90 ] ])
  end

  it "取引関係の無いテナントには、公開品目の行も見えない" do
    expect(visible_prices(FactoryBot.create(:tenant))).to be_empty
  end
end
