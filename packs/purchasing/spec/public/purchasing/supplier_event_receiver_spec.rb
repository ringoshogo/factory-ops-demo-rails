require "rails_helper"
require_relative "../../../../../spec/support/events"
require_relative "../../../../../spec/support/shared_examples/idempotent_receiver"
require_relative "../../../../../spec/support/cross_read"

# 「出荷計上」の購買の受け手（docs/architecture/data-model.md「購買（`purchasing`）」「イベントの受け口と冪等キー」）。
# 配送表を通した重複配送は spec/contracts/shipment_posted_delivery_spec.rb が確かめる
RSpec.describe Purchasing::SupplierEventReceiver do
  include ActiveSupport::Testing::TimeHelpers

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

  # イベントの受け手は操作者のいない入口なので、所有の条件を RLS に任せない。発注を FOR UPDATE で引くので、SELECT だけを開いても
  # RLS の UPDATE のポリシーが他社の発注を除き、条件の抜けが見えない（docs/guides/testing.md「行列テストとの分担」）。
  # どの種類のイベントも同じ 1 か所で発注を引くので、時刻を書く「品番照合待ち」で確かめる
  describe "RLS の SELECT と UPDATE を開いたとき" do
    include_context "RLS の SELECT と UPDATE を開く"

    it "他社の発注は見つからず、書かない" do
      theirs = Tenancy.with_tenant(FactoryBot.create(:tenant).id) { FactoryBot.create(:purchase_order, supplier_tenant_id: supplier.id) }
      pending_event = Contracts::PartMatchPending.new(purchase_order_id: order.id, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id,
        occurred_at: Time.current.iso8601(6))

      Tenancy.with_tenant(buyer.id) do
        cross_read!
        # 対照：開いた後は、他社の発注が見え、自社の発注には品番照合待ちの時刻を書く
        before = reread(theirs)
        described_class.handle(pending_event)
        expect(order.reload.awaiting_match_at).to be_present

        expect { described_class.handle(pending_event.with(purchase_order_id: theirs.id)) }.to raise_error(ActiveRecord::RecordNotFound)
        expect(reread(theirs)).to eq(before)
      end
    end
  end

  describe "取消の回答" do
    let!(:request) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:cancellation_request, purchase_order: order) } }
    let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "") }

    def answer(klass, **overrides)
      klass.new(cancellation_request_id: request.id, purchase_order_id: order.id, buyer_tenant_id: buyer.id,
        supplier_tenant_id: supplier.id, occurred_at: Time.current.iso8601(6), **overrides)
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
      Contracts::SalesOrderCancelled.new(purchase_order_id: order.id, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id,
        occurred_at: Time.current.iso8601(6))
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

  # 発注の時刻列には、受け取った時刻ではなく受注側で起きた時刻を書く。受け取った時刻を書くと、配送が遅れたときに、
  # その後に発注側で出した取消依頼が受注確定より前に並ぶ（docs/architecture/data-model.md「イベントの受け口と冪等キー」）。
  # 発生の時刻を運ぶ前に登録したジョブのペイロードには occurred_at が無く、そのときだけ受け取った時刻を書く
  describe "発生の時刻" do
    let(:occurred_at) { Time.zone.parse("2026-10-14 10:20:30.123456") }
    let(:received_at) { Time.zone.parse("2026-10-15 09:00:00") }
    let!(:request) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:cancellation_request, purchase_order: order) } }
    let(:keys) { { purchase_order_id: order.id, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id } }
    let(:confirmed_lines) { lines.map { { "purchase_order_line_id" => _1.id, "item_name" => "確定名", "unit_price" => "100" } } }

    # イベントごとに、作る引数と、書いた時刻列を読む手続き
    let(:cases) do
      { Contracts::SalesOrderConfirmed => [ { lines: confirmed_lines }, -> { order.reload.accepted_at } ],
        Contracts::PartMatchPending => [ {}, -> { order.reload.awaiting_match_at } ],
        Contracts::CancellationApproved => [ { cancellation_request_id: request.id },
          -> { [ request.reload.decided_at, order.reload.cancelled_at ] } ],
        Contracts::CancellationRejected => [ { cancellation_request_id: request.id }, -> { request.reload.decided_at } ],
        Contracts::SalesOrderCancelled => [ {}, -> { order.reload.supplier_cancelled_at } ] }
    end

    def written(klass, payload)
      travel_to(received_at) { handle(klass.from_payload(payload)) }
      Tenancy.with_tenant(buyer.id) { cases.fetch(klass).last.call }
    end

    def payload(klass) = klass.new(**keys, **cases.fetch(klass).first, occurred_at: occurred_at.iso8601(6)).to_payload

    [ Contracts::SalesOrderConfirmed, Contracts::PartMatchPending, Contracts::CancellationApproved,
      Contracts::CancellationRejected, Contracts::SalesOrderCancelled ].each do |klass|
      it "#{klass.name.demodulize} は、運んだ発生の時刻を書く" do
        expect(Array.wrap(written(klass, payload(klass)))).to all(eq(occurred_at))
      end

      it "#{klass.name.demodulize} の occurred_at の無い古いペイロードでは、受け取った時刻を書く" do
        old = payload(klass).except("occurred_at")

        expect(klass.from_payload(old).occurred_at).to be_nil
        expect(Array.wrap(written(klass, old))).to all(eq(received_at))
      end

      # 同じイベントを 2 回届けると、2 回とも同じ時刻を書くので、空のときだけ書く条件を外しても落ちない。後から別の時刻を運ばせる
      it "#{klass.name.demodulize} を後から別の発生の時刻で届けても、先に書いた時刻を書き換えない" do
        written(klass, payload(klass))
        later = payload(klass).merge("occurred_at" => (occurred_at + 1.hour).iso8601(6))

        expect(Array.wrap(written(klass, later))).to all(eq(occurred_at))
      end
    end

    it "new は occurred_at を求め、発行元が渡し忘れたら例外にする" do
      expect { Contracts::PartMatchPending.new(**keys) }.to raise_error(ArgumentError, /occurred_at/)
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
