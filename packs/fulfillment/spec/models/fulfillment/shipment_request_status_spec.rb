require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

# 導出表の行ごとに出荷依頼を 1 件ずつ作り、状況で絞った一覧にその 1 件だけが返ることを確かめる
# （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
# 各行の出荷依頼は下の行の条件にも当たるように作り、式の優先順を確かめる
RSpec.describe Fulfillment::ShipmentRequestStatus do
  let(:tenant) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }

  around { |example| Tenancy.with_tenant(tenant.id) { example.run } }

  # instructed は有効な出荷指示を、shipped は出荷指示と出荷実績を、held は同じ受注への解除前の出荷停止を作る
  def request(instructed: false, shipped: false, held: false, **attributes)
    FactoryBot.create(:shipment_request, **attributes).tap do |request|
      instruction = FactoryBot.create(:shipping_instruction, shipment_request: request) if instructed || shipped
      FactoryBot.create(:shipment, shipping_instruction: instruction) if shipped
      FactoryBot.create(:shipping_hold, sales_order_id: request.sales_order_id) if held
    end
  end

  def list(statuses)
    page = Fulfillment::ShipmentRequests.list(actor, first: 100, after: nil, filter: { statuses: })
    [ page.values.map { [ _1.id, _1.status ] }, page.total_count ]
  end

  it "導出表の行ごとに、その行の状況で絞った一覧にその出荷依頼だけが返る" do
    requests = {
      cancelled: request(cancelled_at: Time.current, shipped: true, held: true),
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

  it "取り消した出荷指示と、解除した出荷停止は数えない" do
    ready = request
    FactoryBot.create(:shipping_instruction, shipment_request: ready, status: "cancelled")
    FactoryBot.create(:shipping_hold, sales_order_id: ready.sales_order_id, released_at: Time.current)
    # 対照：有効な出荷指示と、解除前の出荷停止は数える
    instructed, held = request(instructed: true), request(held: true)

    expect(list(%i[ready instructed on_hold]))
      .to eq([ [ [ held.id, :on_hold ], [ instructed.id, :instructed ], [ ready.id, :ready ] ], 3 ])
  end

  it "出荷停止は、同じ受注の出荷依頼にだけ効く" do
    held = request(held: true)
    other = request

    expect(list([ :on_hold ])).to eq([ [ [ held.id, :on_hold ] ], 1 ])
    expect(list([ :ready ])).to eq([ [ [ other.id, :ready ] ], 1 ])
  end

  it "複数の状況はどれかに当たる出荷依頼に絞り、空の配列は 0 件、nil は絞らない" do
    cancelled, ready, instructed = request(cancelled_at: Time.current), request, request(instructed: true)

    expect(list(%i[cancelled instructed])).to eq([ [ [ instructed.id, :instructed ], [ cancelled.id, :cancelled ] ], 2 ])
    expect(list([])).to eq([ [], 0 ])
    expect(list(nil)).to eq([ [ [ instructed.id, :instructed ], [ ready.id, :ready ], [ cancelled.id, :cancelled ] ], 3 ])
  end

  # 期待する順は docs/architecture/graphql-schema.md「状況の enum」の「状況で並べる順」の表から書き写す
  it "状況で並べると、業務の進み順に並び、DESC はその逆になる" do
    requests = {
      cancelled: request(cancelled_at: Time.current), shipped: request(shipped: true), on_hold: request(held: true),
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

  # 片方にだけ状況を足すと、足した状況の順位が空になり、状況で並べたときに黙って最後に並ぶ
  it "状況で並べる順（SORT_ORDER）は、導出の優先順（ALL）と同じ状況の集まりを持つ" do
    expect(described_class::SORT_ORDER).to match_array(described_class::ALL)
    expect(described_class::SORT_ORDER.uniq.size).to eq(described_class::SORT_ORDER.size)
  end
end

# 出荷停止は受注の ID を参照するだけで外部キーが無く、他社の名義で自社の受注を指す行を DB は拒まない。
# 式が所有テナントをそろえずに RLS に任せると、RLS を開いたときだけ他社の停止が効く
RSpec.describe Fulfillment::ShipmentRequestStatus, "（RLS の SELECT と UPDATE を開いたとき）" do
  include_context "RLS の SELECT と UPDATE を開く"

  let(:tenant) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }

  it "他社の出荷停止は、自社の受注を指していても効かない" do
    ready = Tenancy.with_tenant(tenant.id) { FactoryBot.create(:shipment_request) }
    Tenancy.with_tenant(FactoryBot.create(:tenant).id) { FactoryBot.create(:shipping_hold, sales_order_id: ready.sales_order_id) }

    Tenancy.with_tenant(tenant.id) do
      cross_read!
      # 対照：開いた後は、他社の名義で自社の受注を指す出荷停止が見える
      expect(Fulfillment::ShippingHold.where(sales_order_id: ready.sales_order_id).count).to eq(1)

      page = Fulfillment::ShipmentRequests.list(actor, first: 100, after: nil, filter: { statuses: [ :ready ] })
      expect([ page.values.map { [ _1.id, _1.status ] }, page.total_count ]).to eq([ [ [ ready.id, :ready ] ], 1 ])
    end
  end
end
