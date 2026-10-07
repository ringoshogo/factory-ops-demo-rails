require "rails_helper"
require_relative "../../../../../spec/support/events"
require_relative "../../../../../spec/support/shared_examples/idempotent_receiver"

# 「出荷可能」の受け手（docs/architecture/data-model.md「イベントの受け口と冪等キー」）
RSpec.describe Fulfillment::SalesEventReceiver do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:buyer) { FactoryBot.create(:tenant) }
  let(:event) do
    Contracts::SalesOrderReadyForShipment.new(sales_order_id: SecureRandom.uuid, supplier_tenant_id: supplier.id,
      buyer_tenant_id: buyer.id, purchase_order_id: SecureRandom.uuid, due_date: "2026-10-31",
      lines: [ { "sales_order_line_id" => SecureRandom.uuid, "purchase_order_line_id" => SecureRandom.uuid,
        "item_id" => SecureRandom.uuid, "quantity" => 4 } ])
  end

  def request_rows = Tenancy.with_tenant(supplier.id) { Fulfillment::ShipmentRequest.count + Fulfillment::ShipmentRequestLine.count }

  it_behaves_like "冪等な受け手" do
    # 受注側が、自社の受注について出す
    let(:publish_event) { -> { Tenancy.with_tenant(supplier.id) { Contracts.publish(event) } } }
    let(:written_rows) { -> { request_rows } }
  end

  it "受注側テナントの名義で、出荷待ちの出荷依頼と明細を写す" do
    Tenancy.with_tenant(supplier.id) { Contracts.publish(event) }
    deliver_enqueued_events

    Tenancy.with_tenant(supplier.id) do
      request = Fulfillment::ShipmentRequest.sole
      expect(request).to have_attributes(owner_tenant_id: supplier.id, sales_order_id: event.sales_order_id, buyer_tenant_id: buyer.id,
        source_purchase_order_id: event.purchase_order_id, due_date: Date.new(2026, 10, 31))
      expect(request.lines.map { _1.slice(:sales_order_line_id, :source_purchase_order_line_id, :item_id, :quantity).values })
        .to eq(event.lines.map(&:values))
    end
  end

  it "同じ受注の出荷依頼がすでにあれば、冪等キーの確認を通り抜けても一意索引が止め、何も書かない" do
    Tenancy.with_tenant(supplier.id) do
      described_class.handle(event)
      allow(Fulfillment::ShipmentRequest).to receive(:exists?).and_return(false)

      expect { described_class.handle(event) }.not_to change(Fulfillment::ShipmentRequest, :count)
    end
  end
end
