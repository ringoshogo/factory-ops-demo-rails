require "rails_helper"

# 同じ受注の取消と出荷の計上を 2 つの接続で同時に動かしても、どちらか一方だけが成立する（重要シナリオ S4 の取消）。
# 受注側の取消と審査の承認は同じ受注の内部の取消の処理を通るので、両方の経路を確かめる。
# 取消は受注 → 受注明細 → 在庫 → 引当、計上は受注 → 出荷依頼 → 出荷指示 → 在庫 → 引当の順にロックを取るので、
# 後の操作は受注の行ロックで先の操作のコミットを待ち、受注の取消済・審査中・出荷済を読み直して中止する
# （docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
RSpec.describe "取消と出荷の計上の競合" do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, :labeled) } }
  # 在庫を 10 入れ、受注の明細 2 つ（3 と 2）を全量で引き当て、同じ明細の出荷依頼に有効な出荷指示を作っておく
  let!(:order) do
    Tenancy.with_tenant(supplier.id) do
      Inventory::Adjustment.adjust(actor, item_id: item.id, type: "inbound", quantity: 10)
      FactoryBot.create(:sales_order, customer_tenant_id: buyer.id).tap do |order|
        [ 3, 2 ].each { FactoryBot.create(:sales_order_line, :matched, sales_order: order, item_id: item.id, quantity: _1) }
        Sales::OrderAllocation.allocate(actor, sales_order_id: order.id)
      end
    end
  end
  let!(:request) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:shipment_request, sales_order_id: order.id, buyer_tenant_id: buyer.id).tap do |request|
        Sales::SalesOrders.lines_for(actor, [ order.id ]).fetch(order.id).each do |line|
          FactoryBot.create(:shipment_request_line, shipment_request: request, sales_order_line_id: line.id, item_id: item.id,
            quantity: line.quantity)
        end
        FactoryBot.create(:shipping_instruction, shipment_request: request)
      end
    end
  end

  after do
    delete_owned_rows([ supplier.id, buyer.id ], %w[
      shipment_lines shipments shipping_instructions shipment_request_lines shipment_requests
      stock_movements allocations stocks item_labels cancellation_reviews sales_order_lines sales_orders item_prices items
    ])
  end

  def post = Fulfillment::Shipping.post(actor, shipment_request_id: request.id, shipped_on: Date.new(2026, 10, 9))

  def cancel = Sales::OrderCancellation.cancel(actor, sales_order_id: order.id)
  def approve = Sales::CancellationReviews.approve(actor, cancellation_review_id: @review_id)

  # 審査は「取消依頼」の受け手で作る。審査の行があることが、そのまま出荷停止になる
  def open_review
    Tenancy.with_tenant(supplier.id) do
      Sales::PurchasingEventReceiver.handle(Contracts::CancellationRequested.new(cancellation_request_id: SecureRandom.uuid,
        purchase_order_id: order.source_purchase_order_id, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id,
        requested_at: Time.current.iso8601(6)))
      @review_id = Sales::CancellationReviews.for_sales_orders(actor, [ order.id ]).fetch(order.id).sole.id
    end
  end

  # [受注の状況, 出荷依頼の状況, 在庫の現在庫と引当]
  def state
    Tenancy.with_tenant(supplier.id) do
      [ Sales::SalesOrders.find(actor, order.id).status, Fulfillment::ShipmentRequests.find(actor, request.id).status,
        Inventory::Stocks.for_items(actor, [ item.id ]).fetch(item.id).to_h.slice(:on_hand, :allocated) ]
    end
  end

  # 後の操作は受注の行を待つ。計上が受注の行をロックしない形なら、計上は在庫の行を待つ。出荷依頼と受注の間の順は、
  # 待つ先の表では分からないので、shipping_spec.rb と instructions_spec.rb のロックの順の example が確かめる
  def expect_waiting_on_order(waiter, by:)
    expect(blocked_on_lock?(waiter, by:)).to be(true)
    expect(waiting_row_tables(waiter)).to eq([ "sales_orders" ])
  end

  context "受注側の取消" do
    it "取消がコミットするまで計上は受注の行を待ち、コミットの後は取消済を読んで CONFLICT になる" do
      cancelled, release, canceller = hold_open(supplier.id) { cancel }
      expect(cancelled).to be_success

      poster = in_thread(supplier.id) { post }
      expect_waiting_on_order(poster, by: canceller)

      expect(commit(release, canceller)).to be_success
      expect(finish(poster).failures.map(&:code)).to eq([ :conflict ])
      expect(state).to eq([ :cancelled, :cancelled, { on_hand: 10, allocated: 0 } ])
    end

    it "計上がコミットするまで取消は受注の行を待ち、コミットの後は出荷済を読んで CONFLICT になる" do
      posted, release, poster = hold_open(supplier.id) { post }
      expect(posted).to be_success

      canceller = in_thread(supplier.id) { cancel }
      expect_waiting_on_order(canceller, by: poster)

      expect(commit(release, poster)).to be_success
      expect(finish(canceller).failures.map(&:code)).to eq([ :conflict ])
      expect(state).to eq([ :shipped, :shipped, { on_hand: 5, allocated: 0 } ])
    end
  end

  context "審査の承認" do
    before { open_review }

    # 審査の行がそのまま出荷停止なので、承認と計上のどちらを先に始めても、未決の審査がある間の計上は成立しない
    it "未決の審査がある間の計上は、承認の前でも審査中で CONFLICT になる" do
      expect(Tenancy.with_tenant(supplier.id) { post }.failures.map(&:code)).to eq([ :conflict ])
      expect(state).to eq([ :allocated, :on_hold, { on_hand: 10, allocated: 5 } ])
    end

    it "承認がコミットするまで計上は受注の行を待ち、コミットの後は取消済を読んで CONFLICT になる" do
      approved, release, approver = hold_open(supplier.id) { approve }
      expect(approved).to be_success

      poster = in_thread(supplier.id) { post }
      expect_waiting_on_order(poster, by: approver)

      expect(commit(release, approver)).to be_success
      expect(finish(poster).failures.map(&:code)).to eq([ :conflict ])
      expect(state).to eq([ :cancelled, :cancelled, { on_hand: 10, allocated: 0 } ])
    end
  end
end
