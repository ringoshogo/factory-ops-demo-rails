require "rails_helper"

# 入出庫の調整の理由の長さの上限（docs/architecture/graphql-schema.md「mutation の一覧」adjustStock）。
# 上限ちょうどと上限 + 1 の両方を、定数から作らずに仕様の値で書く。上限を誤って下げる変更は、上限ちょうどの example が落とす
RSpec.describe Inventory::Adjustment, ".adjust" do
  let(:tenant) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }
  let(:item_id) { SecureRandom.uuid }

  around { |example| Tenancy.with_tenant(tenant.id) { example.run } }

  def adjust(reason) = described_class.adjust(actor, item_id:, type: "inbound", quantity: 3, reason:)

  def movements = Inventory::Stocks.movements(actor, item_id:, first: 100, after: nil).values.map { [ _1.type, _1.quantity, _1.reason ] }

  def stocks = Inventory::Stocks.for_items(actor, [ item_id ]).transform_values(&:on_hand)

  it "理由が上限ちょうどの 200 文字なら受け付け、理由ごと移動履歴に残す" do
    reason = "あ" * 200

    expect(adjust(reason)).to be_success
    expect(movements).to eq([ [ "inbound", 3, reason ] ])
    expect(stocks).to eq(item_id => 3)
  end

  it "理由が 201 文字なら INVALID_INPUT で理由を指し、在庫も移動履歴も書かない" do
    result = adjust("あ" * 201)

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :invalid_input, [ :reason ] ] ])
    expect(movements).to be_empty
    expect(stocks).to be_empty
    # 対照：同じ品目への正しい調整は、同じ読み方で見える
    expect(adjust("棚卸")).to be_success
    expect(movements).to eq([ [ "inbound", 3, "棚卸" ] ])
  end
end
