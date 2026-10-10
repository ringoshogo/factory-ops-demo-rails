require "rails_helper"

# 受注側の腐敗防止層。「発注登録」から受注を 1 件だけ作り、全明細が照合できれば「受注確定」、できなければ「品番照合待ち」を出す。
# 発注側へ返すイベントは、受注側の内部の ID を運ばない（docs/architecture/context-map.md「発注の連結と品番の照合」2〜4）
RSpec.describe Sales::PurchaseOrderTranslator do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  around { |example| Tenancy.with_tenant(supplier.id) { example.run } }

  let!(:item) { FactoryBot.create(:item, code: "BOLT-8", name: "六角ボルト M8", unit_price: 120) }
  let!(:mapping) { FactoryBot.create(:customer_part_mapping, customer_tenant_id: buyer.id, customer_part_number: "MY-BOLT", item:) }
  let(:published) { [] }

  before { allow(Contracts).to receive(:publish).and_wrap_original { |original, event| published << event; original.call(event) } }

  def event_for(*part_numbers, desired_delivery_on: "2026-11-02")
    Contracts::PurchaseOrderPlaced.new(purchase_order_id: SecureRandom.uuid, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id,
      desired_delivery_on:,
      lines: part_numbers.map { { "purchase_order_line_id" => SecureRandom.uuid, "part_number" => _1, "quantity" => 2 } })
  end

  def orders = Sales::SalesOrders.list(actor, first: 10, after: nil).values

  def lines_of(order) = Sales::SalesOrders.lines_for(actor, [ order.id ]).fetch(order.id)

  it "全明細が照合できれば、受注を確定して品目の名前と単価を写し、「受注確定」を出す" do
    event = event_for("MY-BOLT")

    described_class.handle(event)

    expect(orders.sole).to have_attributes(customer_tenant_id: buyer.id, status: :received, due_date: Date.new(2026, 11, 2))
    expect(lines_of(orders.sole).map { [ _1.item_id, _1.item_name, _1.unit_price, _1.tax_rate_percent, _1.quantity ] })
      .to eq([ [ item.id, "六角ボルト M8", 120, 10, 2 ] ])
    expect(published.sole).to have_attributes(class: Contracts::SalesOrderConfirmed, purchase_order_id: event.purchase_order_id,
      lines: [ { "purchase_order_line_id" => event.lines.sole["purchase_order_line_id"], "item_name" => "六角ボルト M8", "unit_price" => "120" } ])
  end

  it "照合できない明細があれば、受注は品番照合待ちで止まり、照合できない明細は品目の写しを持たず、「品番照合待ち」を出す" do
    described_class.handle(event_for("MY-BOLT", "UNKNOWN"))

    expect(orders.sole.status).to eq(:awaiting_part_match)
    expect(lines_of(orders.sole).map { [ _1.customer_part_number, _1.item_id, _1.item_name, _1.unit_price, _1.tax_rate_percent ] })
      .to eq([ [ "MY-BOLT", item.id, "六角ボルト M8", 120, 10 ], [ "UNKNOWN", nil, nil, nil, nil ] ])
    expect(published.map(&:class)).to eq([ Contracts::PartMatchPending ])
  end

  it "別の取引先の同じ品番の対応は、照合に使わない" do
    other_buyer = FactoryBot.create(:tenant)
    FactoryBot.create(:customer_part_mapping, customer_tenant_id: other_buyer.id, customer_part_number: "MY-NUT", item:)

    described_class.handle(event_for("MY-NUT"))

    expect(orders.sole.status).to eq(:awaiting_part_match)
  end

  it "同じ「発注登録」が 2 回届いても、受注は 1 件で、2 回目はイベントを出さない" do
    event = event_for("MY-BOLT")

    2.times { described_class.handle(event) }

    expect(orders.size).to eq(1)
    expect(lines_of(orders.sole).size).to eq(1)
    expect(published.size).to eq(1)
  end

  # 発注側へ返すイベントは、発注・発注明細の ID と受注側テナントだけを指す
  { Contracts::PartMatchPending => %w[MY-BOLT UNKNOWN], Contracts::SalesOrderConfirmed => %w[MY-BOLT] }.each do |event_class, part_numbers|
    it "発注側へ返す #{event_class.name.demodulize} は、受注・受注明細・品目・対応表の ID を運ばない" do
      described_class.handle(event_for(*part_numbers))
      internal_ids = [ orders.sole.id, *lines_of(orders.sole).map(&:id), item.id, mapping.id ]

      expect(published.map(&:class)).to eq([ event_class ])
      expect(published.sole.to_h.to_s).not_to include(*internal_ids)
    end
  end
end
