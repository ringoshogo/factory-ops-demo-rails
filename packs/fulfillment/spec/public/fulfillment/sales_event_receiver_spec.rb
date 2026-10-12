require "rails_helper"
require_relative "../../../../../spec/support/events"
require_relative "../../../../../spec/support/shared_examples/idempotent_receiver"
require_relative "../../../../../spec/support/cross_read"

# 受注からのイベントの出荷の受け手。「出荷可能」「出荷停止」「出荷停止解除」「出荷取消」を冪等に書き、届く順が入れ替わっても、
# 停止や出荷依頼を取り残さない（docs/architecture/data-model.md「イベントの受け口と冪等キー」「イベントの届く順の入れ替わり」）
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

  describe "出荷停止と出荷取消" do
    let(:review_id) { SecureRandom.uuid }
    let(:held) { Contracts::ShippingHeld.new(cancellation_review_id: review_id, sales_order_id: event.sales_order_id, supplier_tenant_id: supplier.id) }
    let(:released) { Contracts::ShippingHoldReleased.new(**held.to_h) }
    let(:cancelled) do
      Contracts::ShipmentCancelled.new(sales_order_id: event.sales_order_id, supplier_tenant_id: supplier.id,
        cancellation_review_id: review_id, ready_for_shipment: true)
    end
    let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

    def handle(event) = Tenancy.with_tenant(supplier.id) { described_class.handle(event) }

    def publish(*events) = Tenancy.with_tenant(supplier.id) { events.each { Contracts.publish(_1) } }

    def holds = Tenancy.with_tenant(supplier.id) { Fulfillment::ShippingHold.order(:id).map { _1.slice(:source_cancellation_review_id, :released_at).values } }

    def request = Tenancy.with_tenant(supplier.id) { Fulfillment::ShipmentRequest.find_by!(sales_order_id: event.sales_order_id) }

    def status = Tenancy.with_tenant(supplier.id) { Fulfillment::ShipmentRequests.find(actor, request.id).status }

    def instruct = Tenancy.with_tenant(supplier.id) { Fulfillment::Instructions.create(actor, shipment_request_id: request.id, planned_date: Date.current) }

    describe "出荷停止" do
      it_behaves_like "冪等な受け手" do
        let(:publish_event) { -> { publish(held) } }
        let(:written_rows) { -> { holds.size } }
      end

      it "受注に解除前の出荷停止を書き、出荷依頼を出荷停止中にする" do
        handle(event)

        handle(held)

        expect(holds).to eq([ [ review_id, nil ] ])
        expect(status).to eq(:on_hold)
      end

      it "出荷依頼がまだ無い受注も止める" do
        handle(held)
        handle(event)

        expect(status).to eq(:on_hold)
      end
    end

    describe "出荷停止解除" do
      it_behaves_like "冪等な受け手" do
        let(:publish_event) { -> { publish(held, released) } }
        let(:written_rows) { -> { Tenancy.with_tenant(supplier.id) { Fulfillment::ShippingHold.where.not(released_at: nil).count } } }
      end

      it "出荷停止を解除し、出荷依頼を元の状況に戻す。2 回目の解除は解除の時刻を変えない" do
        handle(event)
        instruct
        handle(held)

        handle(released)
        released_at = holds.sole.last
        handle(released)

        expect(holds).to eq([ [ review_id, released_at ] ])
        expect(released_at).to be_present
        expect(status).to eq(:instructed)
      end
    end

    describe "出荷取消" do
      it_behaves_like "冪等な受け手" do
        let(:publish_event) { -> { publish(event, held, cancelled) } }
        let(:written_rows) do
          -> { Tenancy.with_tenant(supplier.id) { Fulfillment::ShipmentRequest.where.not(cancelled_at: nil).count + Fulfillment::ShippingHold.where.not(released_at: nil).count } }
        end
      end

      it "出荷依頼を取消済にし、有効な出荷指示を取り消し、受注の出荷停止を解除する" do
        handle(event)
        instruct
        handle(held)

        handle(cancelled)

        expect(request.cancelled_at).to be_present
        expect(Tenancy.with_tenant(supplier.id) { request.instructions.map(&:status) }).to eq([ "cancelled" ])
        expect(holds).to match([ [ review_id, be_present ] ])
        expect(status).to eq(:cancelled)
      end

      it "出荷可能を出していない受注の出荷取消は、出荷依頼を作らずに出荷停止だけを解除する" do
        handle(held)

        handle(cancelled.with(ready_for_shipment: false))

        expect(holds).to match([ [ review_id, be_present ] ])
        expect(Tenancy.with_tenant(supplier.id) { Fulfillment::ShipmentRequest.count }).to eq(0)
      end
    end

    # イベントの受け手は操作者のいない入口なので、所有の条件を RLS に任せない。出荷取消は出荷依頼を FOR UPDATE で引いて書き、
    # 出荷停止を UPDATE で解除するので、SELECT だけを開いても RLS の UPDATE のポリシーが他社の行を除き、条件の抜けが見えない
    # （docs/guides/testing.md「行列テストとの分担」）。他社の受注の出荷依頼と解除前の停止を置き、2 か所を 1 つの example で確かめる
    describe "RLS の SELECT と UPDATE を開いたとき" do
      include_context "RLS の SELECT と UPDATE を開く"

      it "出荷取消は、他社の受注の出荷依頼と出荷停止を書かない" do
        their_order_id = SecureRandom.uuid
        theirs = Tenancy.with_tenant(FactoryBot.create(:tenant).id) do
          [ FactoryBot.create(:shipment_request, sales_order_id: their_order_id),
            FactoryBot.create(:shipping_hold, sales_order_id: their_order_id) ]
        end

        Tenancy.with_tenant(supplier.id) do
          cross_read!
          # 対照：開いた後は、他社の出荷依頼と停止が見え、自社の出荷依頼は取消済にする
          before = theirs.map { reread(_1) }
          described_class.handle(event)
          described_class.handle(cancelled.with(cancellation_review_id: nil))
          expect(Fulfillment::ShipmentRequest.find_by!(owner_tenant_id: supplier.id, sales_order_id: event.sales_order_id).cancelled_at)
            .to be_present

          described_class.handle(cancelled.with(sales_order_id: their_order_id, cancellation_review_id: nil, ready_for_shipment: false))
          expect(theirs.map { reread(_1) }).to eq(before)
        end
      end
    end

    it "審査を経ない取消（審査 ID が空）は、出荷依頼を取消済にし、出荷停止の行を作らない" do
      handle(event)

      handle(cancelled.with(cancellation_review_id: nil))

      expect(status).to eq(:cancelled)
      expect(holds).to be_empty
    end

    describe "届く順の入れ替わり" do
      it "出荷停止解除が出荷停止より先に届くと解除済みの停止を作り、後から届いた出荷停止は何もしない" do
        handle(event)

        handle(released)
        expect(holds).to match([ [ review_id, be_present ] ])
        released_at = holds.sole.last
        handle(held)

        expect(holds).to eq([ [ review_id, released_at ] ])
        expect(status).to eq(:ready)
      end

      it "出荷取消が出荷停止より先に届くと解除済みの停止を作り、後から届いた出荷停止は何もしない" do
        handle(event)

        handle(cancelled)
        expect(holds).to match([ [ review_id, be_present ] ])
        released_at = holds.sole.last
        handle(held)

        expect(holds).to eq([ [ review_id, released_at ] ])
        expect(status).to eq(:cancelled)
      end

      it "出荷取消が出荷可能より先に届くと、何も書かずに失敗し、出荷可能の後の再配送で出荷依頼を取消済にする" do
        expect { handle(cancelled) }.to raise_error(ActiveRecord::RecordNotFound)
        expect(holds).to be_empty

        handle(event)
        handle(cancelled)

        expect(status).to eq(:cancelled)
      end

      it "前の審査の出荷停止解除より、次の審査を承認した出荷取消が先に届いても、両方の停止を解除する" do
        handle(event)
        handle(held.with(cancellation_review_id: SecureRandom.uuid))
        handle(held)

        handle(cancelled)

        expect(holds).to all(match([ be_present, be_present ]))
        expect(holds.size).to eq(2)
      end

      it "前の審査の出荷停止解除より、次の審査の出荷停止が先に届いても、次の審査の停止は残る" do
        handle(event)
        next_held = held.with(cancellation_review_id: SecureRandom.uuid)

        handle(held)
        handle(next_held)
        handle(released)

        expect(holds).to match_array([ [ review_id, be_present ], [ next_held.cancellation_review_id, nil ] ])
        expect(status).to eq(:on_hold)
      end
    end
  end

  it "配送表に無い種類のイベントは、出荷依頼を書かずに ArgumentError で失敗する" do
    unexpected = Contracts::PartMatchPending.new(purchase_order_id: SecureRandom.uuid, buyer_tenant_id: buyer.id,
      supplier_tenant_id: supplier.id)

    expect { Tenancy.with_tenant(supplier.id) { described_class.handle(unexpected) } }
      .to raise_error(ArgumentError, "unexpected event: Contracts::PartMatchPending")
    expect(request_rows).to eq(0)
  end
end
