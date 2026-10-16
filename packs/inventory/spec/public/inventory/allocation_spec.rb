require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

# 引当・解除・消費・受注明細 ID ごとの量と、入出庫の調整（docs/architecture/data-model.md「在庫（`inventory`）」「取消と出荷の競合を止める場所」）
RSpec.describe Inventory::Allocation do
  let(:tenant) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }
  let(:item_id) { SecureRandom.uuid }
  let(:line_ids) { Array.new(2) { SecureRandom.uuid }.sort }

  around { |example| TenantExample.run(example, tenant.id) }

  # 調整は自社の品目の写しのある品目にだけ在庫を作る（Inventory::Adjustment）
  before { FactoryBot.create(:item_label, item_id:) }

  def stock = Inventory::Stocks.for_items(actor, [ item_id ]).fetch(item_id)

  def adjust(type, quantity) = Inventory::Adjustment.adjust(actor, item_id:, type:, quantity:)

  def allocate(*quantities)
    described_class.allocate(actor, line_ids.zip(quantities).map { |id, quantity| { sales_order_line_id: id, item_id:, quantity: } })
  end

  def movements = Inventory::Stocks.movements(actor, item_id:, first: 100, after: nil).values.reverse.map { [ _1.type, _1.quantity ] }

  it "有効在庫の範囲で受注明細 ID の順に引き当て、足りない分は次の引当で埋める" do
    adjust("inbound", 5)

    expect(allocate(3, 4)).to eq(line_ids[0] => 3, line_ids[1] => 2)
    expect(stock.to_h.slice(:on_hand, :allocated, :available)).to eq(on_hand: 5, allocated: 5, available: 0)

    adjust("inbound", 10)
    expect(allocate(3, 4)).to eq(line_ids[0] => 3, line_ids[1] => 4)
    expect(movements).to eq([ [ "inbound", 5 ], [ "allocate", 3 ], [ "allocate", 2 ], [ "inbound", 10 ], [ "allocate", 2 ] ])
  end

  it "引当も調整も、在庫を変えるたびに移動履歴を 1 行足す" do
    expect { adjust("inbound", 5) }.to change { movements.size }.by(1)
    expect { allocate(1, 1) }.to change { movements.size }.by(2)
    expect { adjust("outbound", 2) }.to change { movements.size }.by(1)
    expect { allocate(1, 1) }.not_to(change { movements.size })
  end

  it "有効在庫を超える出庫と、正でない数量・種類の誤りは何も書かずに INVALID_INPUT を返す" do
    adjust("inbound", 5)
    allocate(4, 0)

    [ [ "outbound", 2, :quantity ], [ "inbound", 0, :quantity ], [ "allocate", 1, :type ] ].each do |type, quantity, path|
      result = adjust(type, quantity)
      expect([ result.failures.map(&:code), result.failures.map(&:path) ]).to eq([ [ :invalid_input ], [ [ path ] ] ])
    end
    expect(stock.to_h.slice(:on_hand, :allocated)).to eq(on_hand: 5, allocated: 4)
  end

  it "解除で引当を戻し、解除した引当は数えず、引き当て直さない" do
    adjust("inbound", 5)
    allocate(2, 3)

    expect(described_class.release(actor, [ line_ids[0], SecureRandom.uuid ])).to be_success
    expect(described_class.quantities_for(actor, line_ids)).to eq(line_ids[0] => 0, line_ids[1] => 3)
    expect(allocate(2, 3)).to eq(line_ids[0] => 0, line_ids[1] => 3)
    expect(stock.to_h.slice(:on_hand, :allocated)).to eq(on_hand: 5, allocated: 3)
  end

  it "消費で現在庫と引当を減らし、消費した引当は解除できない" do
    adjust("inbound", 5)
    allocate(2, 3)

    expect(described_class.consume(actor, [ line_ids[0] ])).to be_success
    expect(stock.to_h.slice(:on_hand, :allocated)).to eq(on_hand: 3, allocated: 3)
    expect(described_class.release(actor, line_ids).failures.map(&:code)).to eq([ :conflict ])
    expect(stock.to_h.slice(:on_hand, :allocated)).to eq(on_hand: 3, allocated: 3)
  end

  it "active でない引当か、引当の無い明細の消費は何も変えず CONFLICT を返す" do
    adjust("inbound", 5)
    allocate(2, 0)
    described_class.release(actor, [ line_ids[0] ])

    expect(described_class.consume(actor, [ line_ids[0] ]).failures.map(&:code)).to eq([ :conflict ])
    expect(described_class.consume(actor, [ line_ids[1] ]).failures.map(&:code)).to eq([ :conflict ])
    expect(stock.to_h.slice(:on_hand, :allocated)).to eq(on_hand: 5, allocated: 0)
  end
end

# 受注の状況の式が結ぶ、受注明細 ID ごとの有効な引当数量の副問い合わせ（docs/adr/010）。他社の引当は他社の受注明細を指し、
# 自社の受注明細には結ばれないので、副問い合わせから scope を外しても入口の行列では捕まらない。
# RLS を開き、他社の名義で自社の受注明細を指す引当を見えるようにして確かめる（docs/guides/testing.md「行列テストとの分担」）
RSpec.describe Inventory::Allocation, ".active_quantities_sql" do
  include_context "RLS の SELECT と UPDATE を開く"

  let(:tenant) { FactoryBot.create(:tenant) }
  let(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }
  let(:line_ids) { Array.new(3) { SecureRandom.uuid } }

  def quantities(subquery)
    columns = subquery.columns.values_at(:line_id, :allocated_quantity)
    ActiveRecord::Base.lease_connection.select_rows("SELECT #{columns.join(', ')} FROM (#{subquery.sql}) q").to_h
  end

  it "操作者の scope を掛け、解除した引当を除いて、受注明細 ID ごとの引当数量を返す" do
    Tenancy.with_tenant(other.id) { FactoryBot.create(:allocation, sales_order_line_id: line_ids[0], quantity: 5) }
    Tenancy.with_tenant(tenant.id) do
      FactoryBot.create(:allocation, sales_order_line_id: line_ids[1], quantity: 3, status: "released")
      FactoryBot.create(:allocation, sales_order_line_id: line_ids[2], quantity: 1)
      cross_read!
      # 対照：開いた後は、scope を掛けない同じ条件の副問い合わせに、他社の名義で自社の受注明細を指す引当が入る
      unscoped = Inventory::StockAllocation.where.not(status: "released").group(:sales_order_line_id)
        .select(:sales_order_line_id, Inventory::StockAllocation.arel_table[:quantity].sum.as("quantity"))
      expect(quantities(SqlSubquery.of(unscoped, line_id: "sales_order_line_id", allocated_quantity: "quantity")))
        .to eq(line_ids[0] => 5, line_ids[2] => 1)

      expect(quantities(described_class.active_quantities_sql(actor))).to eq(line_ids[2] => 1)
    end
  end
end
