require "rails_helper"
require_relative "../../../../../spec/support/events"
require_relative "../../../../../spec/support/shared_examples/idempotent_receiver"

# 「出荷計上」の購買の受け手（docs/architecture/data-model.md「購買（`purchasing`）」「イベントの受け口と冪等キー」）。
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

  describe "取消の回答" do
    let!(:request) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:cancellation_request, purchase_order: order) } }
    let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "") }

    def answer(klass, **overrides)
      klass.new(cancellation_request_id: request.id, purchase_order_id: order.id, buyer_tenant_id: buyer.id,
        supplier_tenant_id: supplier.id, **overrides)
    end

    def order_value = Tenancy.with_tenant(buyer.id) { Purchasing::PurchaseOrders.find(actor, order.id) }

    it_behaves_like "冪等な受け手" do
      # 受注側が、審査を承認して出す
      let(:publish_event) { -> { Tenancy.with_tenant(supplier.id) { Contracts.publish(answer(Contracts::CancellationApproved)) } } }
      let(:written_rows) do
        -> { Tenancy.with_tenant(buyer.id) { Purchasing::CancellationRequest.where.not(outcome: nil).count + Purchasing::PurchaseOrder.where.not(cancelled_at: nil).count } }
      end
    end

    it "取消承認で、依頼に承認を記録し、発注を取消済みにする" do
      handle(answer(Contracts::CancellationApproved))

      expect(Tenancy.with_tenant(buyer.id) { request.reload }).to have_attributes(outcome: "approved", decided_at: be_present)
      expect(order_value).to have_attributes(status: :cancelled, cancellation_pending: false)
    end

    it "取消却下で、依頼に却下を記録し、発注は依頼の前の状況に戻る" do
      Tenancy.with_tenant(buyer.id) { order.update!(accepted_at: Time.current) }

      handle(answer(Contracts::CancellationRejected))

      expect(Tenancy.with_tenant(buyer.id) { request.reload }).to have_attributes(outcome: "rejected", decided_at: be_present)
      expect(order_value).to have_attributes(status: :accepted, cancellation_pending: false)
    end

    it "回答が記録済みの依頼には、後から届いた回答を書かない" do
      handle(answer(Contracts::CancellationRejected))
      decided_at = Tenancy.with_tenant(buyer.id) { request.reload.decided_at }

      handle(answer(Contracts::CancellationApproved))

      expect(Tenancy.with_tenant(buyer.id) { request.reload }).to have_attributes(outcome: "rejected", decided_at:)
      expect(order_value.status).to eq(:sent)
    end

    it "別の発注の依頼 ID を運ぶ回答は、依頼を書かずに失敗する" do
      other_request = Tenancy.with_tenant(buyer.id) { FactoryBot.create(:cancellation_request) }

      expect { handle(answer(Contracts::CancellationApproved, cancellation_request_id: other_request.id)) }
        .to raise_error(ActiveRecord::RecordNotFound)
      expect(Tenancy.with_tenant(buyer.id) { other_request.reload.outcome }).to be_nil
    end
  end

  describe "受注取消" do
    let(:cancelled) do
      Contracts::SalesOrderCancelled.new(purchase_order_id: order.id, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id)
    end
    let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "") }

    it_behaves_like "冪等な受け手" do
      # 受注側が、自社の都合で受注を取り消して出す
      let(:publish_event) { -> { Tenancy.with_tenant(supplier.id) { Contracts.publish(cancelled) } } }
      let(:written_rows) { -> { Tenancy.with_tenant(buyer.id) { Purchasing::PurchaseOrder.where.not(supplier_cancelled_at: nil).count } } }
    end

    it "発注を受注側により取消にする" do
      Tenancy.with_tenant(buyer.id) { order.update!(accepted_at: Time.current) }

      handle(cancelled)

      expect(Tenancy.with_tenant(buyer.id) { Purchasing::PurchaseOrders.find(actor, order.id).status }).to eq(:supplier_cancelled)
    end

    it "2 回目の配送は、受注側により取消の時刻を書き換えない" do
      handle(cancelled)
      cancelled_at = Tenancy.with_tenant(buyer.id) { order.reload.supplier_cancelled_at }

      handle(cancelled)

      expect(Tenancy.with_tenant(buyer.id) { order.reload.supplier_cancelled_at }).to eq(cancelled_at)
    end

    it "受注側テナントが一致しない発注は書かない" do
      expect { handle(cancelled.with(supplier_tenant_id: FactoryBot.create(:tenant).id)) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(Tenancy.with_tenant(buyer.id) { order.reload.supplier_cancelled_at }).to be_nil
    end
  end

  it "配送表に無い種類のイベントは、発注を書かずに ArgumentError で失敗する" do
    unexpected = Contracts::PurchaseOrderPlaced.new(purchase_order_id: order.id, buyer_tenant_id: buyer.id,
      supplier_tenant_id: supplier.id, desired_delivery_on: nil, lines: [])

    expect { handle(unexpected) }.to raise_error(ArgumentError, "unexpected event: Contracts::PurchaseOrderPlaced")
    expect(Tenancy.with_tenant(buyer.id) { order.reload.slice(:accepted_at, :awaiting_match_at).values }).to eq([ nil, nil ])
    expect(Tenancy.with_tenant(buyer.id) { Purchasing::InboundShipment.count }).to eq(0)
  end
end
