require "rails_helper"

# 導出表の行ごとに受注を 1 件ずつ作り、状況で絞った一覧にその 1 件だけが返ることを確かめる
# （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
# 各行の受注は下の行の条件にも当たるように作り、式の優先順を確かめる。取消済と出荷済は DB の CHECK 制約で同時に持てない
RSpec.describe Sales::SalesOrderStatus do
  let(:tenant) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }
  let(:now) { Time.current }

  around { |example| Tenancy.with_tenant(tenant.id) { example.run } }

  # allocated は照合済みの明細（数量 2）ごとの引当数量で、0 なら引当を作らない。unmatched は照合前の明細の数で、
  # 品番照合待ちの受注が引当済の条件にも当たるように全量を引き当てる（実際の引当は照合の後にしかできない）
  def order(allocated: [], unmatched: 0, **timestamps)
    FactoryBot.create(:sales_order, **timestamps).tap do |order|
      allocated.each do |quantity|
        line = FactoryBot.create(:sales_order_line, :matched, sales_order: order, quantity: 2)
        FactoryBot.create(:allocation, sales_order_line_id: line.id, quantity:) if quantity.positive?
      end
      unmatched.times do
        line = FactoryBot.create(:sales_order_line, sales_order: order)
        FactoryBot.create(:allocation, sales_order_line_id: line.id, quantity: line.quantity)
      end
    end
  end

  def list(statuses)
    page = Sales::SalesOrders.list(actor, first: 100, after: nil, filter: { statuses: })
    [ page.values.map { [ _1.id, _1.status ] }, page.total_count ]
  end

  it "導出表の行ごとに、その行の状況で絞った一覧にその受注だけが返る" do
    orders = {
      cancelled: order(cancelled_at: now, allocated: [ 2 ], unmatched: 1),
      inspected: order(inspected_at: now, shipped_at: now, allocated: [ 2 ], unmatched: 1),
      shipped: order(shipped_at: now, allocated: [ 2 ], unmatched: 1),
      awaiting_part_match: order(allocated: [ 2 ], unmatched: 1),
      allocated: order(allocated: [ 2, 2 ]),
      partially_allocated: order(allocated: [ 1, 0 ]),
      received: order(allocated: [ 0, 0 ])
    }

    expect(orders.keys).to eq(described_class::ALL)
    orders.each do |status, order|
      expect(list([ status ])).to eq([ [ [ order.id, status ] ], 1 ])
    end
  end

  it "解除した引当は数えない" do
    released = order(allocated: [ 2, 2 ])
    expect(Inventory::Allocation.release(actor, Sales::SalesOrderLine.where(sales_order: released).pluck(:id))).to be_success
    allocated = order(allocated: [ 2, 2 ])

    # 対照：解除していない引当の受注は引当済になる
    expect(list([ :allocated ])).to eq([ [ [ allocated.id, :allocated ] ], 1 ])
    expect(list([ :received ])).to eq([ [ [ released.id, :received ] ], 1 ])
  end

  it "複数の状況はどれかに当たる受注に絞り、空の配列は 0 件、nil は絞らない" do
    cancelled, received, shipped = order(cancelled_at: now), order(allocated: [ 0 ]), order(shipped_at: now)

    expect(list(%i[cancelled shipped])).to eq([ [ [ shipped.id, :shipped ], [ cancelled.id, :cancelled ] ], 2 ])
    expect(list([])).to eq([ [], 0 ])
    expect(list(nil)).to eq([ [ [ shipped.id, :shipped ], [ received.id, :received ], [ cancelled.id, :cancelled ] ], 3 ])
  end

  # 期待する順は docs/architecture/graphql-schema.md「状況の enum」の「状況で並べる順」の表から書き写す
  it "状況で並べると、業務の進み順に並び、DESC はその逆になる" do
    orders = {
      cancelled: order(cancelled_at: now), inspected: order(inspected_at: now, shipped_at: now), shipped: order(shipped_at: now),
      awaiting_part_match: order(unmatched: 1), allocated: order(allocated: [ 2 ]), partially_allocated: order(allocated: [ 1 ]),
      received: order(allocated: [ 0 ])
    }
    sorted = lambda do |direction|
      Sales::SalesOrders.list(actor, first: 100, after: nil, order_by: [ { field: :status, direction: } ]).values.map(&:status)
    end

    expected = %i[awaiting_part_match received partially_allocated allocated shipped inspected cancelled]
    expect(orders.keys).to match_array(expected)
    expect(sorted.call(:asc)).to eq(expected)
    expect(sorted.call(:desc)).to eq(expected.reverse)
  end

  # 片方にだけ状況を足すと、足した状況の順位が空になり、状況で並べたときに黙って最後に並ぶ
  it "状況で並べる順（SORT_ORDER）は、導出の優先順（ALL）と同じ状況の集まりを持つ" do
    expect(described_class::SORT_ORDER).to match_array(described_class::ALL)
    expect(described_class::SORT_ORDER.uniq.size).to eq(described_class::SORT_ORDER.size)
  end
end
