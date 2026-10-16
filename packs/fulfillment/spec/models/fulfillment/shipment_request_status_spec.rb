require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

# 導出表の行ごとに出荷依頼を 1 件ずつ作り、状況で絞った一覧にその 1 件だけが返ることを確かめる
# （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
# 各行の出荷依頼は下の行の条件にも当たるように作り、式の優先順を確かめる
RSpec.describe Fulfillment::ShipmentRequestStatus do
  let(:tenant) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }

  around { |example| TenantExample.run(example, tenant.id) }

  # instructed は有効な出荷指示を、shipped は出荷指示と出荷実績を、held は同じ受注への未決の取消の審査を作り、cancelled は受注を取消済にする
  def request(instructed: false, shipped: false, held: false, cancelled: false)
    order = FactoryBot.create(:sales_order, cancelled_at: (Time.current if cancelled))
    FactoryBot.create(:cancellation_review, sales_order: order) if held
    FactoryBot.create(:shipment_request, sales_order_id: order.id).tap do |request|
      instruction = FactoryBot.create(:shipping_instruction, shipment_request: request) if instructed || shipped
      FactoryBot.create(:shipment, shipping_instruction: instruction) if shipped
    end
  end

  def list(statuses)
    page = Fulfillment::ShipmentRequests.list(actor, first: 100, after: nil, filter: { statuses: })
    [ page.values.map { [ _1.id, _1.status ] }, page.total_count ]
  end

  it "導出表の行ごとに、その行の状況で絞った一覧にその出荷依頼だけが返る" do
    requests = {
      cancelled: request(cancelled: true, shipped: true, held: true),
      shipped: request(shipped: true, held: true),
      on_hold: request(instructed: true, held: true),
      instructed: request(instructed: true),
      ready: request
    }

    expect(requests.keys).to eq(described_class::ALL)
    requests.each do |status, request|
      expect(list([ status ])).to eq([ [ [ request.id, status ] ], 1 ])
    end
  end

  it "取り消した出荷指示と、決着した取消の審査は数えない" do
    ready = request
    FactoryBot.create(:shipping_instruction, shipment_request: ready, status: "cancelled")
    FactoryBot.create(:cancellation_review, sales_order_id: ready.sales_order_id, decision: "rejected", decided_at: Time.current)
    # 対照：有効な出荷指示と、未決の審査は数える
    instructed, held = request(instructed: true), request(held: true)

    expect(list(%i[ready instructed on_hold]))
      .to eq([ [ [ held.id, :on_hold ], [ instructed.id, :instructed ], [ ready.id, :ready ] ], 3 ])
  end

  it "取消の審査は、同じ受注の出荷依頼にだけ効く" do
    held = request(held: true)
    other = request

    expect(list([ :on_hold ])).to eq([ [ [ held.id, :on_hold ] ], 1 ])
    expect(list([ :ready ])).to eq([ [ [ other.id, :ready ] ], 1 ])
  end

  it "複数の状況はどれかに当たる出荷依頼に絞り、空の配列は 0 件、nil は絞らない" do
    cancelled, ready, instructed = request(cancelled: true), request, request(instructed: true)

    expect(list(%i[cancelled instructed])).to eq([ [ [ instructed.id, :instructed ], [ cancelled.id, :cancelled ] ], 2 ])
    expect(list([])).to eq([ [], 0 ])
    expect(list(nil)).to eq([ [ [ instructed.id, :instructed ], [ ready.id, :ready ], [ cancelled.id, :cancelled ] ], 3 ])
  end

  # 期待する順は docs/architecture/graphql-schema.md「状況の enum」の「状況で並べる順」の表から書き写す
  it "状況で並べると、業務の進み順に並び、DESC はその逆になる" do
    requests = {
      cancelled: request(cancelled: true), shipped: request(shipped: true), on_hold: request(held: true),
      instructed: request(instructed: true), ready: request
    }
    sorted = lambda do |direction|
      Fulfillment::ShipmentRequests.list(actor, first: 100, after: nil, order_by: [ { field: :status, direction: } ]).values.map(&:status)
    end

    expected = %i[ready instructed on_hold shipped cancelled]
    expect(requests.keys).to match_array(expected)
    expect(sorted.call(:asc)).to eq(expected)
    expect(sorted.call(:desc)).to eq(expected.reverse)
  end

  # 取消済と出荷停止中は、受注の公開 API の副問い合わせから、イベントを流さずに導出する
  describe "受注の取消と審査" do
    let(:admin) { actor.with(role: "admin") }

    def status(request) = Fulfillment::ShipmentRequests.find(actor, request.id).status

    it "受注を取り消した直後に、その受注の出荷依頼は取消済になる" do
      cancelled, other = request(instructed: true), request(instructed: true)

      expect(Sales::OrderCancellation.cancel(admin, sales_order_id: cancelled.sales_order_id)).to be_success
      expect(status(cancelled)).to eq(:cancelled)
      # 対照：取り消していない受注の出荷依頼は、出荷指示済のまま
      expect(status(other)).to eq(:instructed)
    end

    it "未決の審査がある受注の出荷依頼は出荷停止中になり、審査を却下すると元の状況に戻る" do
      held, other = request(instructed: true), request(instructed: true)
      review = FactoryBot.create(:cancellation_review, sales_order_id: held.sales_order_id)

      expect(status(held)).to eq(:on_hold)
      expect(status(other)).to eq(:instructed)

      expect(Sales::CancellationReviews.reject(admin, cancellation_review_id: review.id)).to be_success
      expect(status(held)).to eq(:instructed)
    end

    it "審査を承認すると取消済になる" do
      held = request
      review = FactoryBot.create(:cancellation_review, sales_order_id: held.sales_order_id)

      expect(Sales::CancellationReviews.approve(admin, cancellation_review_id: review.id)).to be_success
      expect(status(held)).to eq(:cancelled)
    end
  end

  # 片方にだけ状況を足すと、足した状況の順位が空になり、状況で並べたときに黙って最後に並ぶ
  it "状況で並べる順（SORT_ORDER）は、導出の優先順（ALL）と同じ状況の集まりを持つ" do
    expect(described_class::SORT_ORDER).to match_array(described_class::ALL)
    expect(described_class::SORT_ORDER.uniq.size).to eq(described_class::SORT_ORDER.size)
  end
end

# 出荷依頼は受注を ID で参照するだけで外部キーが無く、他社の受注を指す出荷依頼を DB は拒まない。
# 式が受注の副問い合わせを scope で自社に限らずに RLS に任せると、RLS を開いたときだけ他社の受注の取消と審査が効く
RSpec.describe Fulfillment::ShipmentRequestStatus, "（RLS の SELECT と UPDATE を開いたとき）" do
  include_context "RLS の SELECT と UPDATE を開く"

  let(:tenant) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }

  it "他社の受注の取消と審査は、出荷依頼がその受注を指していても効かず、出荷待ちになる" do
    cancelled, reviewed = Tenancy.with_tenant(FactoryBot.create(:tenant).id) do
      [ FactoryBot.create(:sales_order, cancelled_at: Time.current),
        FactoryBot.create(:sales_order).tap { FactoryBot.create(:cancellation_review, sales_order: _1) } ]
    end
    requests = Tenancy.with_tenant(tenant.id) do
      [ cancelled, reviewed ].map { FactoryBot.create(:shipment_request, sales_order_id: _1.id) }
    end

    Tenancy.with_tenant(tenant.id) do
      cross_read!
      # 対照：開いた後は、他社の取消済の受注と未決の審査が見える
      counts = ApplicationRecord.lease_connection.select_rows(<<~SQL, nil, [ cancelled.id, reviewed.id ]).first
        SELECT (SELECT count(*) FROM sales_orders WHERE id = $1 AND cancelled_at IS NOT NULL),
               (SELECT count(*) FROM cancellation_reviews WHERE sales_order_id = $2 AND decision IS NULL)
      SQL
      expect(counts).to eq([ 1, 1 ])

      page = Fulfillment::ShipmentRequests.list(actor, first: 100, after: nil, filter: { statuses: [ :ready ] })
      expect([ page.values.map { [ _1.id, _1.status ] }, page.total_count ]).to eq([ requests.reverse.map { [ _1.id, :ready ] }, 2 ])
    end
  end
end
