require "rails_helper"
# 「出荷計上」の受注の受け手（docs/architecture/data-model.md「イベントの受け口と冪等キー」）。
# 配送表を通した重複配送は spec/contracts/shipment_posted_delivery_spec.rb が確かめる
RSpec.describe Sales::FulfillmentEventReceiver do
  include ActiveSupport::Testing::TimeHelpers

  let(:supplier) { FactoryBot.create(:tenant) }
  let(:buyer) { FactoryBot.create(:tenant) }
  let!(:order) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:sales_order, customer_tenant_id: buyer.id) } }
  let(:event) do
    Contracts::ShipmentPosted.new(shipment_id: SecureRandom.uuid, sales_order_id: order.id,
      purchase_order_id: order.source_purchase_order_id, supplier_tenant_id: supplier.id, buyer_tenant_id: buyer.id,
      shipped_on: "2026-10-09", lines: [])
  end

  def shipped_at = Tenancy.with_tenant(supplier.id) { order.reload.shipped_at }

  it "受注側テナントの名義で、受注に shipped_at を 1 回だけ書く" do
    Tenancy.with_tenant(supplier.id) { described_class.handle(event) }
    first = shipped_at

    travel 1.hour do
      Tenancy.with_tenant(supplier.id) { described_class.handle(event) }
    end

    expect(first).to be_present
    expect(shipped_at).to eq(first)
  end

  it "発注側テナントが一致しない受注は書かない" do
    other = event.with(buyer_tenant_id: FactoryBot.create(:tenant).id)

    expect { Tenancy.with_tenant(supplier.id) { described_class.handle(other) } }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
