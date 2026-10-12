require "rails_helper"

# 同じ品目への改定の予約と訂正を 2 つの接続で同時に動かしても、品目の行ロックで直列になる。
# 後の操作は、先の操作が閉じた行と足した行を読んでから、自分の行を閉じて足す（docs/adr/006 決定 3）
RSpec.describe Sales::ItemPrices do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "admin", partner_code: "") }
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, unit_price: 100) } }
  let(:first_day) { Date.current + 10 }
  let(:second_day) { Date.current + 20 }

  after do
    delete_owned_rows([ supplier.id ], %w[item_prices items])
  end

  def schedule(unit_price, effective_on) = described_class.schedule(actor, item_id: item.id, unit_price:, effective_on:)

  def prices = Tenancy.with_tenant(supplier.id) { described_class.history(actor, [ item.id ]).fetch(item.id) }

  # 後の予約が品目のロックを待たないと、先の予約が閉じる前の (,) の行を読んで閉じようとし、閉じた行を閉じられずに失敗する
  it "先の予約がコミットするまで後の予約は待ち、先の予約が足した行を分けて、両方の改定を残す" do
    _, release, first = hold_open(supplier.id) { schedule(120, first_day) }

    second = in_thread(supplier.id) { schedule(130, second_day) }
    expect(blocked_on_lock?(second, by: first)).to be(true)

    commit(release, first)
    expect(finish(second)).to be_success
    expect(prices.map { [ _1.unit_price, _1.valid_from, _1.valid_to ] })
      .to eq([ [ 100, nil, first_day ], [ 120, first_day, second_day ], [ 130, second_day, nil ] ])
  end

  it "予約がコミットするまで訂正は待ち、予約が閉じた行の訂正は CONFLICT で何も書かない" do
    original = prices.sole
    _, release, scheduler = hold_open(supplier.id) { schedule(120, first_day) }

    corrector = in_thread(supplier.id) { described_class.correct(actor, item_price_id: original.id, unit_price: 90, reason: "入力の誤り") }
    expect(blocked_on_lock?(corrector, by: scheduler)).to be(true)

    commit(release, scheduler)
    expect(finish(corrector).failures.map(&:code)).to eq([ :conflict ])
    expect(prices.map(&:unit_price)).to eq([ 100, 120 ])
  end
end
