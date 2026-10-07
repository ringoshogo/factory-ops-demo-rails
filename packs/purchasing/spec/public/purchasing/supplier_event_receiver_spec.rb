require "rails_helper"

# 「出荷計上」の購買の受け手（docs/architecture/data-model.md「購買」「イベントの受け口と冪等キー」）。
# 配送表を通した重複配送は spec/contracts/shipment_posted_delivery_spec.rb が確かめる
RSpec.describe Purchasing::SupplierEventReceiver do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:buyer) { FactoryBot.create(:tenant) }
  let!(:order) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:purchase_order, supplier_tenant_id: supplier.id) } }
  let!(:lines) { Tenancy.with_tenant(buyer.id) { FactoryBot.create_list(:purchase_order_line, 2, purchase_order: order, quantity: 5) } }
  let(:event) do
    Contracts::ShipmentPosted.new(shipment_id: SecureRandom.uuid, sales_order_id: SecureRandom.uuid, purchase_order_id: order.id,
      supplier_tenant_id: supplier.id, buyer_tenant_id: buyer.id, shipped_on: "2026-10-09",
      lines: lines.map { { "sales_order_line_id" => SecureRandom.uuid, "purchase_order_line_id" => _1.id, "quantity" => _1.quantity } })
  end

  def handle(event) = Tenancy.with_tenant(buyer.id) { described_class.handle(event) }

  it "発注側テナントの名義で、出荷を入荷として明細ごとに写し、発注を入荷予定にする" do
    handle(event)

    Tenancy.with_tenant(buyer.id) do
      shipment = Purchasing::InboundShipment.sole
      expect(shipment).to have_attributes(owner_tenant_id: buyer.id, purchase_order_id: order.id, shipment_id: event.shipment_id,
        shipped_on: Date.new(2026, 10, 9))
      expect(shipment.lines.map { [ _1.purchase_order_line_id, _1.shipped_quantity ] }).to eq(lines.map { [ _1.id, 5 ] })
      actor = Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "")
      expect(Purchasing::PurchaseOrders.find(actor, order.id).status).to eq(:inbound)
    end
  end

  it "受注 ID と受注明細 ID を保存しない" do
    handle(event)

    columns = Purchasing::InboundShipment.column_names + Purchasing::InboundShipmentLine.column_names
    expect(columns.grep(/sales_order/)).to be_empty
  end

  it "同じ出荷が 2 回届いても、入荷は 1 件である" do
    handle(event)
    handle(event)

    expect(Tenancy.with_tenant(buyer.id) { [ Purchasing::InboundShipment.count, Purchasing::InboundShipmentLine.count ] }).to eq([ 1, 2 ])
  end

  it "受注側テナントが一致しない発注は書かない" do
    expect { handle(event.with(supplier_tenant_id: FactoryBot.create(:tenant).id)) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
