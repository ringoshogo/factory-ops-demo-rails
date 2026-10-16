require "rails_helper"

# 同じ出荷依頼への計上どうしと、計上と出荷指示の取消を 2 つの接続で同時に動かしても、どちらか一方だけが成立する。
# 出荷依頼の行ロックが同じ出荷依頼への操作を直列にする。取消の審査の作成と決着は受注の行ロックを取り、出荷指示の作成と計上も
# 受注の行を最初にロックするので、審査は計上と出荷指示の作成の途中に割り込まない
# （docs/architecture/data-model.md「取消と出荷の競合を止める場所」「出荷（`fulfillment`）」）
RSpec.describe Fulfillment::Shipping do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:item_id) { SecureRandom.uuid }
  let(:instructed) { true }
  # 在庫を 10 入れ、出荷依頼の明細 2 つ（3 と 2）を全量で引き当て、有効な出荷指示を作っておく
  let!(:request) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:item_label, item_id:)
      Inventory::Adjustment.adjust(actor, item_id:, type: "inbound", quantity: 10)
      FactoryBot.create(:shipment_request).tap do |request|
        FactoryBot.create(:shipping_instruction, shipment_request: request) if instructed
        [ 3, 2 ].each do |quantity|
          line = FactoryBot.create(:shipment_request_line, shipment_request: request, item_id:, quantity:)
          Inventory::Allocation.allocate(actor, [ { sales_order_line_id: line.sales_order_line_id, item_id:, quantity: } ])
        end
      end
    end
  end

  after do
    delete_owned_rows([ supplier.id, request.buyer_tenant_id ], %w[
      shipment_lines shipments shipping_instructions shipment_request_lines shipment_requests
      stock_movements allocations stocks item_labels cancellation_reviews sales_orders
    ])
  end

  def post = described_class.post(actor, shipment_request_id: request.id, shipped_on: Date.new(2026, 10, 9))
  def cancel = Fulfillment::Instructions.cancel(actor, shipment_request_id: request.id)

  def shipped
    Tenancy.with_tenant(supplier.id) do
      [ Fulfillment::Shipment.where(shipment_request_id: request.id).count,
        Inventory::Stocks.for_items(actor, [ item_id ]).fetch(item_id).to_h.slice(:on_hand, :allocated) ]
    end
  end

  def instruction_statuses = Tenancy.with_tenant(supplier.id) { request.instructions.pluck(:status) }

  it "同じ出荷依頼の計上が同時に来ると、後の計上は先の計上のコミットを待ち、CONFLICT になる。出荷実績は 1 件だけできる" do
    posted, release, poster = hold_open(supplier.id) { post }
    expect(posted).to be_success

    second = in_thread(supplier.id) { post }
    expect(blocked_on_lock?(second, by: poster)).to be(true)

    expect(commit(release, poster)).to be_success
    expect(finish(second).failures.map(&:code)).to eq([ :conflict ])
    expect(shipped).to eq([ 1, { on_hand: 5, allocated: 0 } ])
  end

  it "計上がコミットするまで出荷指示の取消は待ち、コミットの後は CONFLICT になる" do
    posted, release, poster = hold_open(supplier.id) { post }
    expect(posted).to be_success

    canceller = in_thread(supplier.id) { cancel }
    expect(blocked_on_lock?(canceller, by: poster)).to be(true)

    expect(commit(release, poster)).to be_success
    expect(finish(canceller).failures.map(&:code)).to eq([ :conflict ])
    expect(instruction_statuses).to eq([ "active" ])
    expect(shipped).to eq([ 1, { on_hand: 5, allocated: 0 } ])
  end

  it "出荷指示の取消がコミットするまで計上は待ち、コミットの後は CONFLICT になる" do
    cancelled, release, canceller = hold_open(supplier.id) { cancel }
    expect(cancelled).to be_success

    poster = in_thread(supplier.id) { post }
    expect(blocked_on_lock?(poster, by: canceller)).to be(true)

    expect(commit(release, canceller)).to be_success
    expect(finish(poster).failures.map(&:code)).to eq([ :conflict ])
    expect(instruction_statuses).to eq([ "cancelled" ])
    expect(shipped).to eq([ 0, { on_hand: 10, allocated: 5 } ])
  end

  describe "取消の審査" do
    let(:admin) { actor.with(role: "admin") }
    let(:requested) do
      Contracts::CancellationRequested.new(cancellation_request_id: SecureRandom.uuid, purchase_order_id: request.source_purchase_order_id,
        buyer_tenant_id: request.buyer_tenant_id, supplier_tenant_id: supplier.id, requested_at: Time.current.iso8601(6))
    end

    def receive_request = Sales::PurchasingEventReceiver.handle(requested)
    def create_instruction = Fulfillment::Instructions.create(actor, shipment_request_id: request.id, planned_date: Date.new(2026, 10, 20))

    # [未決の審査と決着した審査の決着, 出荷依頼の状況]
    def review_state
      Tenancy.with_tenant(supplier.id) do
        reviews = Sales::CancellationReviews.for_sales_orders(actor, [ request.sales_order_id ]).fetch(request.sales_order_id)
        [ reviews.map(&:decision), Fulfillment::ShipmentRequests.find(actor, request.id).status ]
      end
    end

    it "審査の作成がコミットするまで計上は受注の行を待ち、コミットの後は審査中で CONFLICT になる" do
      _, release, receiver = hold_open(supplier.id) { receive_request }

      poster = in_thread(supplier.id) { post }
      expect(blocked_on_lock?(poster, by: receiver)).to be(true)

      commit(release, receiver)
      expect(finish(poster).failures.map(&:code)).to eq([ :conflict ])
      expect(shipped).to eq([ 0, { on_hand: 10, allocated: 5 } ])
      expect(review_state).to eq([ [ nil ], :on_hold ])
    end

    # 受け手は受注をロックしてから出荷済を読むので、計上のコミットの後は出荷済の受注として審査を作らずに自動で却下する
    it "計上がコミットするまで審査の作成は待ち、コミットの後は出荷済を読んで未決の審査を残さない" do
      posted, release, poster = hold_open(supplier.id) { post }
      expect(posted).to be_success

      receiver = in_thread(supplier.id) { receive_request }
      expect(blocked_on_lock?(receiver, by: poster)).to be(true)

      commit(release, poster)
      finish(receiver)
      expect(shipped).to eq([ 1, { on_hand: 5, allocated: 0 } ])
      expect(review_state).to eq([ [], :shipped ])
    end

    it "審査の却下がコミットするまで計上は待ち、コミットの後は読み直して計上が成立する" do
      review = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:cancellation_review, sales_order_id: request.sales_order_id) }
      rejected, release, rejecter = hold_open(supplier.id) { Sales::CancellationReviews.reject(admin, cancellation_review_id: review.id) }
      expect(rejected).to be_success

      poster = in_thread(supplier.id) { post }
      expect(blocked_on_lock?(poster, by: rejecter)).to be(true)

      commit(release, rejecter)
      expect(finish(poster)).to be_success
      expect(shipped).to eq([ 1, { on_hand: 5, allocated: 0 } ])
      expect(review_state).to eq([ [ :rejected ], :shipped ])
    end

    context "出荷指示の無い出荷依頼" do
      let(:instructed) { false }

      it "審査の作成がコミットするまで出荷指示の作成は待ち、コミットの後は審査中で CONFLICT になる" do
        _, release, receiver = hold_open(supplier.id) { receive_request }

        creator = in_thread(supplier.id) { create_instruction }
        expect(blocked_on_lock?(creator, by: receiver)).to be(true)

        commit(release, receiver)
        expect(finish(creator).failures.map(&:code)).to eq([ :conflict ])
        expect(instruction_statuses).to eq([])
        expect(review_state).to eq([ [ nil ], :on_hold ])
      end

      it "出荷指示の作成がコミットするまで審査の作成は待ち、コミットの後は審査ができ、その後の計上は CONFLICT になる" do
        created, release, creator = hold_open(supplier.id) { create_instruction }
        expect(created).to be_success

        receiver = in_thread(supplier.id) { receive_request }
        expect(blocked_on_lock?(receiver, by: creator)).to be(true)

        commit(release, creator)
        finish(receiver)
        expect(review_state).to eq([ [ nil ], :on_hold ])
        expect(Tenancy.with_tenant(supplier.id) { post }.failures.map(&:code)).to eq([ :conflict ])
        expect(shipped).to eq([ 0, { on_hand: 10, allocated: 5 } ])
      end
    end
  end
end
