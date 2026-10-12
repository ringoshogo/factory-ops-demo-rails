require "rails_helper"

# 同じ受注の取消と出荷の計上を 2 つの接続で同時に動かしても、どちらか一方だけが成立する（重要シナリオ S4 の取消）。
# 受注側の取消と審査の承認は同じ受注の内部の取消の処理を通るので、両方の経路を確かめる。
# 取消は受注 → 受注明細 → 在庫 → 引当、計上は出荷依頼 → 出荷指示 → 在庫 → 引当の順にロックを取るので、
# 後の操作は在庫の行ロックで先の操作のコミットを待ち、引当の状態を見て中止する
# （docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
RSpec.describe "取消と出荷の計上の競合" do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:item) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item) } }
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
      shipment_lines shipments shipping_instructions shipping_holds shipment_request_lines shipment_requests
      stock_movements allocations stocks cancellation_reviews sales_order_lines sales_orders items
    ])
  end

  def post = Fulfillment::Shipping.post(actor, shipment_request_id: request.id, shipped_on: Date.new(2026, 10, 9))

  # 受注側の取消か、審査の承認で受注を取り消す
  def cancel(path)
    case path
    when :supplier then Sales::OrderCancellation.cancel(actor, sales_order_id: order.id)
    when :review then Sales::CancellationReviews.approve(actor, cancellation_review_id: @review_id)
    end
  end

  # 審査は「取消依頼」の受け手で作る。受け手が出した「出荷停止」は流さない。停止は業務の手順で、
  # このテストは手順をすり抜けた同時の操作を、在庫の行 → 引当の行の順に取る行ロックが止めることを確かめるからである
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

  { "受注側の取消" => :supplier, "審査の承認" => :review }.each do |name, path|
    context name do
      before { open_review if path == :review }

      it "取消がコミットするまで計上は待ち、コミットの後は引当が解除されているので CONFLICT になる" do
        cancelled, release, canceller = hold_open(supplier.id) { cancel(path) }
        expect(cancelled).to be_success

        poster = in_thread(supplier.id) { post }
        expect(blocked_on_lock?(poster, by: canceller)).to be(true)

        expect(commit(release, canceller)).to be_success
        expect(finish(poster).failures.map(&:code)).to eq([ :conflict ])
        expect(state).to eq([ :cancelled, :instructed, { on_hand: 10, allocated: 0 } ])
      end

      it "計上がコミットするまで取消は待ち、コミットの後は引当が消費済みなので CONFLICT になる" do
        posted, release, poster = hold_open(supplier.id) { post }
        expect(posted).to be_success

        canceller = in_thread(supplier.id) { cancel(path) }
        expect(blocked_on_lock?(canceller, by: poster)).to be(true)

        expect(commit(release, poster)).to be_success
        expect(finish(canceller).failures.map(&:code)).to eq([ :conflict ])
        expect(state).to eq([ :allocated, :shipped, { on_hand: 5, allocated: 0 } ])
      end
    end
  end
end
