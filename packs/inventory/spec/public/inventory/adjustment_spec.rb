require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

# 入出庫の調整の理由の長さの上限（docs/architecture/graphql-schema.md「mutation の一覧」adjustStock）。
# 上限ちょうどと上限 + 1 の両方を、定数から作らずに仕様の値で書く。上限を誤って下げる変更は、上限ちょうどの example が落とす
RSpec.describe Inventory::Adjustment, ".adjust" do
  let(:tenant) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }
  let(:item_id) { SecureRandom.uuid }

  around { |example| TenantExample.run(example, tenant.id) }

  before { FactoryBot.create(:item_label, item_id:) }

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

  around { |example| TenantExample.run(example, tenant.id) }

  before { FactoryBot.create(:item_label, item_id:) }

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

# 在庫は自社の品目にだけできる。調整と在庫数の設定は、自社の品目の写しで品目を確かめ、写しの無い品目 ID を何も書かずに
# NOT_FOUND にする（docs/architecture/data-model.md「在庫（`inventory`）」）
RSpec.describe Inventory::Adjustment, "の品目の確かめ" do
  let!(:tenant) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }
  let(:own_item_id) { Tenancy.with_tenant(tenant.id) { FactoryBot.create(:item_label).item_id } }
  let(:their_item_id) { Tenancy.with_tenant(other.id) { FactoryBot.create(:item_label).item_id } }

  operations = {
    adjust: ->(actor, item_id) { Inventory::Adjustment.adjust(actor, item_id:, type: "inbound", quantity: 3) },
    set_quantity: ->(actor, item_id) { Inventory::Adjustment.set_quantity(actor, item_id:, quantity: 3, reason: "CSV の取り込み") }
  }

  def failures(result) = result.failures.map { [ _1.code, _1.path ] }

  # 品目 ID ごとの在庫の行の数と移動履歴の数
  def written(item_id) = [ Inventory::Stocks.for_items(actor, [ item_id ]).size,
    Inventory::Stocks.movements(actor, item_id:, first: 100, after: nil).total_count ]

  operations.each do |name, operation|
    it "#{name} は、写しの無い品目 ID と他社の写しの品目 ID を NOT_FOUND にし、在庫の行も移動履歴も作らない" do
      own, theirs, unlabeled = own_item_id, their_item_id, SecureRandom.uuid

      Tenancy.with_tenant(tenant.id) do
        # 対照：自社の写しの品目なら、在庫の行を作って調整する
        expect(operation.call(actor, own)).to be_success
        expect(written(own)).to eq([ 1, 1 ])

        [ theirs, unlabeled ].each do |item_id|
          expect(failures(operation.call(actor, item_id))).to eq([ [ :not_found, [ :item_id ] ] ])
          expect(written(item_id)).to eq([ 0, 0 ])
        end
      end
    end
  end

  # RLS が他社の写しを隠すので、確かめから所有の条件を外しても上の example は落ちない。RLS の SELECT と UPDATE を開き、
  # 他社の写しが見える状態で確かめる（docs/guides/testing.md「行列テストとの分担」）
  describe "RLS の SELECT と UPDATE を開いたとき" do
    include_context "RLS の SELECT と UPDATE を開く"

    operations.each do |name, operation|
      it "#{name} は、見えるようになった他社の写しの品目 ID も NOT_FOUND にする" do
        own, theirs = own_item_id, their_item_id

        Tenancy.with_tenant(tenant.id) do
          cross_read!
          # 対照：開いた後は他社の写しが見え、自社の写しの品目なら調整する
          expect(Inventory::ItemLabel.where(item_id: theirs).pluck(:owner_tenant_id)).to eq([ other.id ])
          expect(operation.call(actor, own)).to be_success

          expect(failures(operation.call(actor, theirs))).to eq([ [ :not_found, [ :item_id ] ] ])
          expect(Inventory::Stock.where(item_id: theirs)).to be_empty
          expect(Inventory::StockMovement.where(item_id: theirs)).to be_empty
        end
      end
    end
  end
end
