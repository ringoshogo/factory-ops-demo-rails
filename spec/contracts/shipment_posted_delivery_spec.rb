require "rails_helper"
require_relative "../support/events"
require_relative "../support/shared_examples/idempotent_receiver"

# 1 つの「出荷計上」が、受注と購買の 2 つの宛先テナントでそれぞれ 1 回だけ処理される
# （docs/implementation-plan.md M14 の完了条件、docs/architecture/data-model.md「イベントの受け口と冪等キー」）
RSpec.describe "出荷計上の配送" do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let!(:purchase_order_line) do
    Tenancy.with_tenant(buyer.id) { FactoryBot.create(:purchase_order_line, quantity: 4, purchase_order: FactoryBot.create(:purchase_order, supplier_tenant_id: supplier.id)) }
  end
  let!(:sales_order) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:sales_order, customer_tenant_id: buyer.id, source_purchase_order_id: purchase_order_line.purchase_order_id)
    end
  end
  let(:event) do
    Contracts::ShipmentPosted.new(shipment_id: SecureRandom.uuid, sales_order_id: sales_order.id,
      purchase_order_id: purchase_order_line.purchase_order_id, supplier_tenant_id: supplier.id, buyer_tenant_id: buyer.id,
      shipped_on: "2026-10-09",
      lines: [ { "sales_order_line_id" => SecureRandom.uuid, "purchase_order_line_id" => purchase_order_line.id, "quantity" => 4 } ])
  end

  # 出荷が、自社の出荷実績について出す
  def publish = Tenancy.with_tenant(supplier.id) { Contracts.publish(event) }

  # 受け手の表はパッケージの外から読めないので、SQL で数える
  def count(tenant, sql) = Tenancy.with_tenant(tenant.id) { ActiveRecord::Base.lease_connection.select_value(sql) }
  def shipped_orders = count(supplier, "SELECT count(*) FROM sales_orders WHERE shipped_at IS NOT NULL")
  def inbound_rows = count(buyer, "SELECT (SELECT count(*) FROM inbound_shipments) + (SELECT count(*) FROM inbound_shipment_lines)")

  it "受注の受け手は受注側テナント、購買の受け手は発注側テナントを宛先にして、1 件ずつ登録される" do
    publish

    expect(enqueued_event_jobs.map { |job| job.arguments["arguments"].values_at(2, 3) }).to contain_exactly(
      [ "Sales::FulfillmentEventReceiver", supplier.id ], [ "Purchasing::SupplierEventReceiver", buyer.id ]
    )
  end

  it "どちらの宛先も、重複して届いても 1 回分だけ書く" do
    publish
    deliver_enqueued_events(times: 2)

    expect([ shipped_orders, inbound_rows ]).to eq([ 1, 2 ])
  end

  it_behaves_like "冪等な受け手" do
    let(:publish_event) { -> { publish } }
    let(:written_rows) { -> { [ shipped_orders, inbound_rows ].sum } }
  end
end
