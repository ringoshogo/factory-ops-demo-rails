require "rails_helper"

# 同じ「出荷可能」が 2 つの接続へ同時に届いても、出荷依頼は 1 件だけできる。後の配送は冪等キーの確認を通り抜けるが、
# 一意索引の上で先の配送のコミットを待ち、何も書かずに終わる（docs/architecture/data-model.md「イベントの受け口と冪等キー」）
RSpec.describe Fulfillment::SalesEventReceiver do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:event) do
    Contracts::SalesOrderReadyForShipment.new(sales_order_id: SecureRandom.uuid, sales_order_no: "SO-000042", supplier_tenant_id: supplier.id,
      buyer_tenant_id: buyer.id, purchase_order_id: SecureRandom.uuid, due_date: "2026-10-31",
      lines: [ { "sales_order_line_id" => SecureRandom.uuid, "purchase_order_line_id" => SecureRandom.uuid,
        "item_id" => SecureRandom.uuid, "quantity" => 4 } ])
  end

  after do
    delete_owned_rows([ supplier.id, buyer.id ], %w[shipment_request_lines shipment_requests])
  end

  it "先の配送がコミットするまで後の配送は一意索引で待ち、後の配送は例外を出さずに何も書かない" do
    _, release, first = hold_open(supplier.id) { described_class.handle(event) }

    second = in_thread(supplier.id) { described_class.handle(event) }
    expect(blocked_on_lock?(second, by: first)).to be(true)

    # 先の配送のコミットと、後の配送のどちらにも例外が出ない
    expect { commit(release, first) }.not_to raise_error
    expect { finish(second) }.not_to raise_error
    expect(Tenancy.with_tenant(supplier.id) { [ Fulfillment::ShipmentRequest.count, Fulfillment::ShipmentRequestLine.count ] })
      .to eq([ 1, 1 ])
  end
end
