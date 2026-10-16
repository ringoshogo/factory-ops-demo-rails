require "rails_helper"

# 出荷実績の計上。有効な指示のある出荷依頼を、有効な引当を消費して全量で 1 回だけ計上し、ロックを決まった順に取る
# （docs/architecture/data-model.md「取消と出荷の競合を止める場所」「出荷（`fulfillment`）」）
RSpec.describe Fulfillment::Shipping do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  around { |example| TenantExample.run(example, supplier.id) }

  let(:item_id) { SecureRandom.uuid }
  let(:request) { FactoryBot.create(:shipping_instruction).shipment_request }
  # 出荷依頼の明細ごとに、在庫を入れて全量を引き当てておく
  let!(:lines) do
    Inventory::Adjustment.adjust(actor, item_id:, type: "inbound", quantity: 10)
    [ 3, 2 ].map do |quantity|
      FactoryBot.create(:shipment_request_line, shipment_request: request, item_id:, quantity:).tap do |line|
        Inventory::Allocation.allocate(actor, [ { sales_order_line_id: line.sales_order_line_id, item_id:, quantity: } ])
      end
    end
  end

  def post = described_class.post(actor, shipment_request_id: request.id, shipped_on: Date.new(2026, 10, 9))
  def stock = Inventory::Stocks.for_items(actor, [ item_id ]).fetch(item_id)
  def line_ids = lines.map(&:sales_order_line_id)
  def movements = Inventory::Stocks.movements(actor, item_id:, first: 100, after: nil).values.map { [ _1.type, _1.quantity ] }

  it "計上で引当が consumed になり、現在庫と引当が減り、出荷の移動履歴が明細ごとに残る" do
    expect(post.value.status).to eq(:shipped)

    expect(stock).to have_attributes(on_hand: 5, allocated: 0, available: 5)
    expect(movements.select { _1.first == "ship" }).to contain_exactly([ "ship", 3 ], [ "ship", 2 ])
    # 消費した引当は数量を数え続け、解除できない
    expect(Inventory::Allocation.quantities_for(actor, line_ids).values).to eq([ 3, 2 ])
    expect(Inventory::Allocation.release(actor, line_ids).failures.map(&:code)).to eq([ :conflict ])
    expect(request.reload.shipment.lines.map { [ _1.shipment_request_line_id, _1.quantity ] })
      .to eq(lines.map { [ _1.id, _1.quantity ] })
  end

  it "出荷計上は、購買が要る ID と、読む受け手の無い受注 ID・受注明細 ID を含めて、明細ごとの受注明細 ID・発注明細 ID・数量を運ぶ" do
    expect(Contracts).to receive(:publish) do |event|
      expect(event).to be_a(Contracts::ShipmentPosted)
      expect(event.to_payload).to include("sales_order_id" => request.sales_order_id, "purchase_order_id" => request.source_purchase_order_id,
        "supplier_tenant_id" => supplier.id, "buyer_tenant_id" => request.buyer_tenant_id, "shipped_on" => "2026-10-09")
      expect(event.lines).to eq(lines.map do
        { "sales_order_line_id" => _1.sales_order_line_id, "purchase_order_line_id" => _1.source_purchase_order_line_id,
          "quantity" => _1.quantity }
      end)
    end

    post
  end

  {
    "解除した引当" => ->(lines, actor) { Inventory::Allocation.release(actor, [ lines.first.sales_order_line_id ]) },
    "消費済みの引当" => ->(lines, actor) { Inventory::Allocation.consume(actor, [ lines.first.sales_order_line_id ]) },
    "引当の無い明細" => ->(lines, _actor) { FactoryBot.create(:shipment_request_line, shipment_request: lines.first.shipment_request) }
  }.each do |name, prepare|
    it "#{name}を含む出荷依頼の計上は CONFLICT で、出荷実績も在庫も変わらない" do
      prepare.call(lines, actor)
      before = [ stock, movements ]

      expect(Contracts).not_to receive(:publish)
      expect(post.failures.map(&:code)).to eq([ :conflict ])
      expect(request.reload.shipment).to be_nil
      expect([ stock, movements ]).to eq(before)
    end
  end

  # 受注の出荷済は、イベントを流さずに、計上と同じトランザクションで書く
  it "計上の直後に、出荷依頼の受注は出荷済になる" do
    expect(Sales::SalesOrders.find(actor, request.sales_order_id).status).not_to eq(:shipped)

    post

    expect(Sales::SalesOrders.find(actor, request.sales_order_id).status).to eq(:shipped)
  end

  describe "受注の取消と審査" do
    let(:admin) { actor.with(role: "admin") }

    {
      "取消済の受注" => ->(request, admin) { Sales::OrderCancellation.cancel(admin, sales_order_id: request.sales_order_id) },
      "未決の審査がある受注" => ->(request, _admin) { FactoryBot.create(:cancellation_review, sales_order_id: request.sales_order_id) }
    }.each do |name, prepare|
      it "#{name}の出荷依頼は計上せず CONFLICT で、出荷実績も在庫も変わらない" do
        prepare.call(request, admin)
        before = [ stock, movements ]

        expect(Contracts).not_to receive(:publish)
        expect(post.failures.map(&:code)).to eq([ :conflict ])
        expect(request.reload.shipment).to be_nil
        expect([ stock, movements ]).to eq(before)
        expect(Inventory::Allocation.quantities_for(actor, line_ids).values).to eq([ 3, 2 ])
      end
    end

    it "未決の審査を却下すると計上できる" do
      review = FactoryBot.create(:cancellation_review, sales_order_id: request.sales_order_id)
      expect(post.failures.map(&:code)).to eq([ :conflict ])

      expect(Sales::CancellationReviews.reject(admin, cancellation_review_id: review.id)).to be_success
      expect(post.value.status).to eq(:shipped)
    end
  end

  # 出荷依頼は受注を ID で参照するだけなので、受注の行の無い出荷依頼を DB は拒まない。計上すると受注の出荷済を書けないまま出荷実績ができる
  it "受注の行の無い出荷依頼は計上せず、出荷依頼 ID を指す NOT_FOUND を返し、出荷実績も在庫も変わらない" do
    request.update!(sales_order_id: SecureRandom.uuid)
    before = [ stock, movements ]

    expect(Contracts).not_to receive(:publish)
    result = post

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :shipment_request_id ] ] ])
    expect(request.reload.shipment).to be_nil
    expect([ stock, movements ]).to eq(before)
  end

  # 受注の出荷済の書き込みが失敗したら、出荷実績と引当の消費もセーブポイントまで戻す
  it "受注の出荷済を書けなければ、出荷依頼 ID を指す NOT_FOUND を返し、出荷実績も在庫も変えない" do
    allow(Sales::OrderShipping).to receive(:mark_shipped).and_return(OperationResult.failure(:not_found, path: [ :sales_order_id ]))
    before = [ stock, movements ]

    expect(post.failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :shipment_request_id ] ] ])
    expect(request.reload.shipment).to be_nil
    expect([ stock, movements ]).to eq(before)
    expect(Inventory::Allocation.quantities_for(actor, line_ids).values).to eq([ 3, 2 ])
  end

  it "有効な指示の無い出荷依頼と、出荷済みの出荷依頼は計上しない" do
    post
    expect(post.failures.map(&:code)).to eq([ :conflict ])

    request.instructions.update_all(status: "cancelled")
    other = FactoryBot.create(:shipment_request)
    expect(described_class.post(actor, shipment_request_id: other.id, shipped_on: Date.current).failures.map(&:code)).to eq([ :conflict ])
  end

  it "見えない出荷依頼は計上せず、出荷依頼 ID を指す NOT_FOUND を返し、在庫も変わらない" do
    result = described_class.post(actor, shipment_request_id: SecureRandom.uuid, shipped_on: Date.current)

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :shipment_request_id ] ] ])
    expect(stock).to have_attributes(on_hand: 10, allocated: 5)
  end

  it "ロックを受注 → 出荷依頼 → 出荷指示 → 在庫（item_id 昇順）→ 引当（受注明細 ID 順）の順に取る" do
    locks = []
    callback = lambda do |*, payload|
      locks << payload[:sql][/FROM "(\w+)"/, 1] + payload[:sql][/ORDER BY (.*?)(?: LIMIT \$\d+)? FOR UPDATE/, 1].to_s if payload[:sql].include?("FOR UPDATE")
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { post }

    expect(locks).to eq([
      "sales_orders",
      "shipment_requests",
      %(shipping_instructions"shipping_instructions"."id" ASC),
      %(stocks"stocks"."item_id" ASC),
      %(allocations"allocations"."sales_order_line_id" ASC)
    ])
  end
end
