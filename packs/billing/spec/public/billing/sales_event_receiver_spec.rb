require "rails_helper"
require_relative "../../../../../spec/support/events"
require_relative "../../../../../spec/support/shared_examples/idempotent_receiver"

# 受注からの「請求対象確定」の受け手。受注側テナントの名義で、未請求の請求対象明細を 1 行書く。
# 冪等キーは出荷実績 ID と受注明細 ID の組（docs/architecture/context-map.md「検収と請求の流れ」4、
# docs/architecture/data-model.md「イベントの受け口と冪等キー」）
RSpec.describe Billing::SalesEventReceiver do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:event) do
    Contracts::BillableItemConfirmed.new(supplier_tenant_id: supplier.id, buyer_tenant_id: buyer.id, shipment_id: SecureRandom.uuid,
      sales_order_line_id: SecureRandom.uuid, purchase_order_line_id: SecureRandom.uuid, item_name: "六角ボルト M8",
      unit_price: "120", tax_rate_percent: 8, quantity: 3, inspected_on: "2026-10-21")
  end

  def handle(event) = Tenancy.with_tenant(supplier.id) { described_class.handle(event) }

  def items
    Tenancy.with_tenant(supplier.id) do
      Billing::BillableItem.order(:id).map do |item|
        item.attributes.symbolize_keys.slice(:owner_tenant_id, :customer_tenant_id, :shipment_id, :sales_order_line_id,
          :source_purchase_order_line_id, :item_name, :unit_price, :quantity, :tax_rate_percent, :inspected_on, :invoice_id)
      end
    end
  end

  it_behaves_like "冪等な受け手" do
    # 受注側が、自社の請求へ出す
    let(:publish_event) { -> { Tenancy.with_tenant(supplier.id) { Contracts.publish(event) } } }
    let(:written_rows) { -> { items.size } }
  end

  it "受注側テナントの名義で、発注側テナントを取引先にした未請求の明細を書く" do
    handle(event)

    expect(items).to eq([ { owner_tenant_id: supplier.id, customer_tenant_id: buyer.id, shipment_id: event.shipment_id,
      sales_order_line_id: event.sales_order_line_id, source_purchase_order_line_id: event.purchase_order_line_id,
      item_name: "六角ボルト M8", unit_price: 120, quantity: 3, tax_rate_percent: 8, inspected_on: Date.new(2026, 10, 21),
      invoice_id: nil } ])
  end

  it "同じ出荷実績の別の受注明細は、別の明細として書く" do
    handle(event)
    handle(event.with(sales_order_line_id: SecureRandom.uuid))

    expect(items.size).to eq(2)
  end

  it "請求済みの明細に同じイベントがもう一度届いても、未請求の明細を作り直さない" do
    handle(event)
    invoice = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:invoice, :issued, customer_tenant_id: buyer.id) }
    Tenancy.with_tenant(supplier.id) { Billing::BillableItem.update_all(invoice_id: invoice.id) }

    handle(event)

    expect(items.map { _1[:invoice_id] }).to eq([ invoice.id ])
  end

  it "配送表に無い種類のイベントは、明細を書かずに ArgumentError で失敗する" do
    unexpected = Contracts::PartMatchPending.new(purchase_order_id: SecureRandom.uuid, buyer_tenant_id: buyer.id,
      supplier_tenant_id: supplier.id)

    expect { handle(unexpected) }.to raise_error(ArgumentError, "unexpected event: Contracts::PartMatchPending")
    expect(items).to be_empty
  end
end
