require "rails_helper"
require_relative "../support/concurrency"

# 同じ品目の引当と出庫が 2 つの接続で同時に進んでも、有効在庫が負にならない。在庫の行ロックが 2 つを直列にし、
# 後の操作は先の操作がコミットした後の有効在庫で判断する（docs/architecture/data-model.md「在庫」）
RSpec.describe "引当と出庫の競合" do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:item_id) { SecureRandom.uuid }
  let(:sales_order_line_id) { SecureRandom.uuid }

  before { Tenancy.with_tenant(supplier.id) { Inventory::Adjustment.adjust(actor, item_id:, type: "inbound", quantity: 10) } }

  after do
    finish_concurrent_threads
    delete_owned_rows([ supplier.id ], %w[stock_movements allocations stocks])
  end

  def allocate(quantity) = Inventory::Allocation.allocate(actor, [ { sales_order_line_id:, item_id:, quantity: } ])
  def outbound(quantity) = Inventory::Adjustment.adjust(actor, item_id:, type: "outbound", quantity:)

  def stock
    Tenancy.with_tenant(supplier.id) { Inventory::Stocks.for_items(actor, [ item_id ]).fetch(item_id).to_h.slice(:on_hand, :allocated, :available) }
  end

  it "引当がコミットするまで出庫は待ち、コミットの後は残りの有効在庫を超える出庫を INVALID_INPUT で拒否する" do
    allocated, release, allocator = hold_open(supplier.id) { allocate(8) }
    expect(allocated).to eq(sales_order_line_id => 8)

    remover = in_thread(supplier.id) { outbound(5) }
    expect(blocked_on_lock?(remover)).to be(true)

    release << true
    allocator.join
    expect(remover.value.failures.map(&:code)).to eq([ :invalid_input ])
    expect(stock).to eq(on_hand: 10, allocated: 8, available: 2)
  end

  it "出庫がコミットするまで引当は待ち、コミットの後は残りの有効在庫だけを引き当てる" do
    removed, release, remover = hold_open(supplier.id) { outbound(7) }
    expect(removed).to be_success

    allocator = in_thread(supplier.id) { allocate(8) }
    expect(blocked_on_lock?(allocator)).to be(true)

    release << true
    remover.join
    expect(allocator.value).to eq(sales_order_line_id => 3)
    expect(stock).to eq(on_hand: 3, allocated: 3, available: 0)
  end
end
