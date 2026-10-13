require "rails_helper"

# 導出表の行ごとに発注を 1 件ずつ作り、状況で絞った一覧にその 1 件だけが返ることを確かめる
# （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
# 各行の発注は下の行の条件にも当たるように作り、式の優先順を確かめる
RSpec.describe Purchasing::PurchaseOrderStatus do
  let(:tenant) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "") }
  let(:now) { Time.current }

  around { |example| Tenancy.with_tenant(tenant.id) { example.run } }

  # inbound は入荷を、inspected は入荷とその検収を作る
  def order(inbound: false, inspected: false, **timestamps)
    FactoryBot.create(:purchase_order, **timestamps).tap do |order|
      shipment = FactoryBot.create(:inbound_shipment, purchase_order: order) if inbound || inspected
      FactoryBot.create(:receipt_inspection, inbound_shipment: shipment) if inspected
    end
  end

  def list(statuses)
    page = Purchasing::PurchaseOrders.list(actor, first: 100, after: nil, filter: { statuses: })
    [ page.values.map { [ _1.id, _1.status ] }, page.total_count ]
  end

  it "導出表の行ごとに、その行の状況で絞った一覧にその発注だけが返る" do
    orders = {
      supplier_cancelled: order(supplier_cancelled_at: now, accepted_at: now, awaiting_match_at: now, inspected: true),
      cancelled: order(cancelled_at: now, accepted_at: now, awaiting_match_at: now, inspected: true),
      inspected: order(accepted_at: now, awaiting_match_at: now, inspected: true),
      inbound: order(accepted_at: now, awaiting_match_at: now, inbound: true),
      # 照合待ちの後で照合でき、受注確定が届いた発注も受注済になる
      accepted: order(accepted_at: now, awaiting_match_at: now),
      awaiting_supplier_confirmation: order(awaiting_match_at: now),
      sent: order
    }

    expect(orders.keys).to eq(described_class::ALL)
    orders.each do |status, order|
      expect(list([ status ])).to eq([ [ [ order.id, status ] ], 1 ])
    end
  end

  it "複数の状況はどれかに当たる発注に絞り、空の配列は 0 件、nil は絞らない" do
    cancelled, sent, inbound = order(cancelled_at: now), order, order(inbound: true)

    expect(list(%i[cancelled inbound])).to eq([ [ [ inbound.id, :inbound ], [ cancelled.id, :cancelled ] ], 2 ])
    expect(list([])).to eq([ [], 0 ])
    expect(list(nil)).to eq([ [ [ inbound.id, :inbound ], [ sent.id, :sent ], [ cancelled.id, :cancelled ] ], 3 ])
  end

  # 片方にだけ状況を足すと、足した状況の順位が空になり、状況で並べたときに黙って最後に並ぶ
  it "状況で並べる順（SORT_ORDER）は、導出の優先順（ALL）と同じ状況の集まりを持つ" do
    expect(described_class::SORT_ORDER).to match_array(described_class::ALL)
    expect(described_class::SORT_ORDER.uniq.size).to eq(described_class::SORT_ORDER.size)
  end
end
