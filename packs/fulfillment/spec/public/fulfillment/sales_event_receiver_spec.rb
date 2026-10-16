require "rails_helper"
require_relative "../../../../../spec/support/events"
require_relative "../../../../../spec/support/shared_examples/idempotent_receiver"
require_relative "../../../../../spec/support/cross_read"

# 受注からの「出荷可能」の出荷の受け手。出荷依頼を冪等に書き、取消の後に届いても状況は受注から導出する
# （docs/architecture/data-model.md「イベントの受け口と冪等キー」「イベントの届く順の入れ替わり」）
RSpec.describe Fulfillment::SalesEventReceiver do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:buyer) { FactoryBot.create(:tenant) }
  let(:event) do
    Contracts::SalesOrderReadyForShipment.new(sales_order_id: SecureRandom.uuid, sales_order_no: "SO-000042", supplier_tenant_id: supplier.id,
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
        source_purchase_order_id: event.purchase_order_id, due_date: Date.new(2026, 10, 31), sales_order_no: "SO-000042")
      expect(request.lines.map { _1.slice(:sales_order_line_id, :source_purchase_order_line_id, :item_id, :quantity).values })
        .to eq(event.lines.map(&:values))
    end
  end

  # 受注番号を運ぶ前に登録したジョブのペイロードは sales_order_no を持たない。読めずに再配送を繰り返さず、受注番号の空の出荷依頼を作り、
  # 作り直しのタスクが埋める
  it "受注番号を持たないペイロードから読んだイベントでも、受注番号の空の出荷依頼を作る。new は受注番号を求める" do
    payload = event.to_payload.except("sales_order_no")
    Tenancy.with_tenant(supplier.id) { described_class.handle(Contracts::SalesOrderReadyForShipment.from_payload(payload)) }

    Tenancy.with_tenant(supplier.id) do
      expect(Fulfillment::ShipmentRequest.sole).to have_attributes(sales_order_id: event.sales_order_id, sales_order_no: nil)
    end
    expect { Contracts::SalesOrderReadyForShipment.new(**payload.symbolize_keys) }.to raise_error(ArgumentError, /sales_order_no/)
    # 対照：受注番号のあるペイロードは、その値で読む
    expect(Contracts::SalesOrderReadyForShipment.from_payload(event.to_payload).sales_order_no).to eq("SO-000042")
  end

  it "同じ受注の出荷依頼がすでにあれば、冪等キーの確認を通り抜けても一意索引が止め、何も書かない" do
    Tenancy.with_tenant(supplier.id) do
      described_class.handle(event)
      allow(Fulfillment::ShipmentRequest).to receive(:exists?).and_return(false)

      expect { described_class.handle(event) }.not_to change(Fulfillment::ShipmentRequest, :count)
    end
  end

  # 受注の取消と出荷可能はどちらも受注側で起き、出荷可能のイベントだけが遅れて届くことがある。出荷依頼の状況は受注の取消から導出するので、
  # 受け手は取消を読まずに出荷依頼を作る
  it "受注を取り消した後に届いた「出荷可能」でも出荷依頼を作り、状況は取消済になる" do
    actor = Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "")
    cancelled, live = Tenancy.with_tenant(supplier.id) do
      [ FactoryBot.create(:sales_order, customer_tenant_id: buyer.id, cancelled_at: Time.current),
        FactoryBot.create(:sales_order, customer_tenant_id: buyer.id) ]
    end

    Tenancy.with_tenant(supplier.id) do
      [ cancelled, live ].each do |order|
        described_class.handle(event.with(sales_order_id: order.id, lines: event.lines.map { _1.merge("sales_order_line_id" => SecureRandom.uuid) }))
      end
      statuses = Fulfillment::ShipmentRequests.for_sales_orders(actor, [ cancelled.id, live.id ]).transform_values(&:status)
      # 対照：取り消していない受注の出荷依頼は出荷待ち
      expect(statuses).to eq(cancelled.id => :cancelled, live.id => :ready)
    end
  end

  it "配送表に無い種類のイベントは、出荷依頼を書かずに ArgumentError で失敗する" do
    unexpected = Contracts::PartMatchPending.new(purchase_order_id: SecureRandom.uuid, buyer_tenant_id: buyer.id,
      supplier_tenant_id: supplier.id, occurred_at: Time.current.iso8601(6))

    expect { Tenancy.with_tenant(supplier.id) { described_class.handle(unexpected) } }
      .to raise_error(ArgumentError, "unexpected event: Contracts::PartMatchPending")
    expect(request_rows).to eq(0)
  end
end
