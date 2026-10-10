require "rails_helper"

# 得意先品番の対応表の登録と、照合待ちの受注の照合し直し（docs/architecture/context-map.md「発注の連結と品番の照合」5）
RSpec.describe Sales::PartMappings do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:customer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  around { |example| Tenancy.with_tenant(supplier.id) { example.run } }

  before { FactoryBot.create(:partnership, buyer_tenant_id: customer.id) }

  let(:item) { FactoryBot.create(:item, name: "六角ボルト M8", unit_price: 120) }

  # 一覧のテストの規則で、親を 2 件以上作る（docs/architecture/graphql-schema.md「ページングと N+1」）
  it "照合待ちの受注が 2 件あると、登録で両方の明細を照合して確定し、受注ごとに「受注確定」を出す" do
    orders = Array.new(2) do
      FactoryBot.create(:sales_order, customer_tenant_id: customer.id).tap do |order|
        FactoryBot.create(:sales_order_line, sales_order: order, customer_part_number: "MY-BOLT")
        FactoryBot.create(:sales_order_line, :matched, sales_order: order)
      end
    end
    confirmed = []
    allow(Contracts).to receive(:publish).and_wrap_original { |original, event| confirmed << event; original.call(event) }

    result = described_class.register(actor, customer_tenant_id: customer.id, customer_part_number: "MY-BOLT", item_id: item.id)

    expect(result).to be_success
    expect(Sales::SalesOrders.by_ids(actor, orders.map(&:id)).values.map(&:status)).to all(eq(:received))
    expect(confirmed.map(&:purchase_order_id)).to match_array(orders.map(&:source_purchase_order_id))
    expect(confirmed.map { _1.lines.map { |line| line["item_name"] } }).to all(include("六角ボルト M8"))
  end
end
