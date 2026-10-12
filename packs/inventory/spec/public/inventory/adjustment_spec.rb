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

# 目標の在庫数に合わせる調整（docs/architecture/data-model.md「取り込み（`imports`）」の在庫の行）。
# 在庫の行をロックしてから差を取り、差を入庫か出庫で移す。引当済みの数量より少なくはできない
RSpec.describe Inventory::Adjustment, ".set_quantity" do
  let(:tenant) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }
  let(:item_id) { SecureRandom.uuid }

  around { |example| Tenancy.with_tenant(tenant.id) { example.run } }

  def set(quantity) = described_class.set_quantity(actor, item_id:, quantity:, reason: "CSV の取り込み")

  def movements = Inventory::Stocks.movements(actor, item_id:, first: 100, after: nil).values.map { [ _1.type, _1.quantity, _1.reason ] }.reverse

  def stock = Inventory::Stocks.for_items(actor, [ item_id ]).fetch(item_id)

  it "在庫の行の無い品目は 0 から入庫し、多ければ入庫、少なければ出庫で差を移す" do
    expect(set(5)).to be_success
    expect(set(8)).to be_success
    expect(set(2).value).to have_attributes(on_hand: 2)

    expect(movements).to eq([ [ "inbound", 5, "CSV の取り込み" ], [ "inbound", 3, "CSV の取り込み" ], [ "outbound", 6, "CSV の取り込み" ] ])
  end

  it "目標がいまの数量と同じなら、移動履歴を足さずに成功する" do
    set(4)

    expect(set(4).value).to have_attributes(on_hand: 4)
    expect(movements.size).to eq(1)
  end

  it "引当済みの数量ちょうどまでは減らせ、それより少ない目標は INVALID_INPUT で、在庫も移動履歴も変えない" do
    set(5)
    Inventory::Allocation.allocate(actor, [ { sales_order_line_id: SecureRandom.uuid, item_id:, quantity: 3 } ])

    result = set(2)

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :invalid_input, [ :quantity ] ] ])
    expect([ stock.on_hand, stock.allocated ]).to eq([ 5, 3 ])
    expect(set(3).value).to have_attributes(on_hand: 3, allocated: 3, available: 0)
  end

  it "負の数と整数でない数は INVALID_INPUT で、在庫の行も作らない" do
    [ -1, 1.5, "3" ].each do |quantity|
      expect(set(quantity).failures.map(&:path)).to eq([ [ :quantity ] ]), quantity.inspect
    end
    expect(Inventory::Stocks.for_items(actor, [ item_id ])).to be_empty
  end
end
