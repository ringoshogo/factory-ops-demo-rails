require "rails_helper"

# 同じ品目を 2 つの受注が同時に引き当てても、有効在庫を超えて引き当てない（docs/architecture/data-model.md「在庫（`inventory`）」）
RSpec.describe Sales::OrderAllocation do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item) } }
  let!(:orders) do
    Tenancy.with_tenant(supplier.id) do
      Inventory::Adjustment.adjust(actor, item_id: item.id, type: "inbound", quantity: 10)
      Array.new(2) do
        FactoryBot.create(:sales_order).tap { FactoryBot.create(:sales_order_line, :matched, sales_order: _1, item_id: item.id, quantity: 10) }
      end
    end
  end

  # 全量を引き当てた受注の「出荷可能」のジョブも、受注側のテナントの分として消す
  after do
    delete_owned_rows([ supplier.id, *orders.map(&:customer_tenant_id) ],
      %w[stock_movements allocations stocks sales_order_lines sales_orders items])
  end

  it "先の引当がコミットするまで後の引当は在庫の行で待ち、後の引当は残りの有効在庫だけを引き当てる" do
    first_result, release, first = hold_open(supplier.id) { described_class.allocate(actor, sales_order_id: orders[0].id) }
    expect(first_result).to be_success

    second = in_thread(supplier.id) { described_class.allocate(actor, sales_order_id: orders[1].id) }
    expect(blocked_on_lock?(second, by: first)).to be(true)

    expect([ commit(release, first).value.status, finish(second).value.status ]).to eq(%i[allocated received])
    Tenancy.with_tenant(supplier.id) do
      expect(Inventory::Stocks.for_items(actor, [ item.id ]).fetch(item.id).to_h.slice(:on_hand, :allocated))
        .to eq(on_hand: 10, allocated: 10)
      line_ids = Sales::SalesOrders.lines_for(actor, orders.map(&:id)).values.flatten.map(&:id)
      expect(Inventory::Allocation.quantities_for(actor, line_ids).values.sum).to eq(10)
    end
  end
end
