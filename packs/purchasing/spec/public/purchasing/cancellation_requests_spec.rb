require "rails_helper"

# 発注側の取消依頼。回答待ちの依頼の重複と取消済みの発注への依頼は CONFLICT にし、出荷済みかどうかは購買では見ない。
# 失敗は、依頼も「取消依頼」も残さない（docs/architecture/context-map.md「取消の流れ」1）
RSpec.describe Purchasing::Ordering, ".request_cancellation" do
  let!(:buyer) { FactoryBot.create(:tenant) }
  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:order) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:purchase_order, supplier_tenant_id: supplier.id) } }

  let(:published) { [] }

  before { allow(Contracts).to receive(:publish).and_wrap_original { |original, event| published << event; original.call(event) } }

  def request_cancellation(purchase_order_id: order.id, reason: "数量の誤り")
    Tenancy.with_tenant(buyer.id) { described_class.request_cancellation(actor, purchase_order_id:, reason:) }
  end

  def requests = Tenancy.with_tenant(buyer.id) { Purchasing::CancellationRequest.order(:id).to_a }

  def find_order = Tenancy.with_tenant(buyer.id) { Purchasing::PurchaseOrders.find(actor, order.id) }

  it "回答待ちの依頼を登録して「取消依頼」を出し、発注は元の状況のまま取消依頼中になる" do
    result = request_cancellation

    expect(result).to be_success
    expect(result.value).to have_attributes(id: order.id, status: :sent, cancellation_pending: true)
    request = requests.sole
    expect(request).to have_attributes(purchase_order_id: order.id, reason: "数量の誤り", outcome: nil, decided_at: nil)
    expect(published.sole).to have_attributes(class: Contracts::CancellationRequested, cancellation_request_id: request.id,
      purchase_order_id: order.id, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id,
      requested_at: request.created_at.iso8601(6))
  end

  it "取消の理由を「取消依頼」に載せない" do
    request_cancellation

    expect(published.sole.to_payload.values).not_to include("数量の誤り")
  end

  it "回答待ちの依頼がある発注への依頼は CONFLICT で、2 件目を残さない" do
    request_cancellation

    expect(request_cancellation.failures.map(&:code)).to eq([ :conflict ])
    expect(requests.size).to eq(1)
    expect(published.size).to eq(1)
  end

  it "却下の回答が届いた後は、同じ発注にもう一度依頼できる" do
    request_cancellation
    Tenancy.with_tenant(buyer.id) { requests.sole.update!(outcome: "rejected", decided_at: Time.current) }

    expect(request_cancellation).to be_success
    expect(requests.map(&:outcome)).to eq([ "rejected", nil ])
  end

  { "取消済み" => :cancelled_at, "受注側により取消" => :supplier_cancelled_at }.each do |name, column|
    it "#{name}の発注への依頼は CONFLICT で、依頼もイベントも残さない" do
      Tenancy.with_tenant(buyer.id) { order.update!(column => Time.current) }

      expect(request_cancellation.failures.map(&:code)).to eq([ :conflict ])
      expect(requests).to be_empty
      expect(published).to be_empty
    end
  end

  it "入荷予定（出荷済み）の発注にも依頼できる。出荷済みかどうかは受注側が見る" do
    Tenancy.with_tenant(buyer.id) { FactoryBot.create(:inbound_shipment, purchase_order: order) }

    expect(request_cancellation.value).to have_attributes(status: :inbound, cancellation_pending: true)
  end

  it "見えない発注は NOT_FOUND" do
    other = FactoryBot.create(:tenant)
    others_order = Tenancy.with_tenant(other.id) { FactoryBot.create(:purchase_order) }

    [ SecureRandom.uuid, others_order.id ].each do |id|
      expect(request_cancellation(purchase_order_id: id).failures.map { [ _1.code, _1.path ] })
        .to eq([ [ :not_found, [ :purchase_order_id ] ] ])
    end
    expect(published).to be_empty
  end

  it "理由が空か長すぎれば INVALID_INPUT で、理由を指す" do
    [ "", " ", "あ" * (described_class::MAX_REASON_LENGTH + 1) ].each do |reason|
      expect(request_cancellation(reason:).failures.map { [ _1.code, _1.path ] }).to eq([ [ :invalid_input, [ :reason ] ] ])
    end
    expect(request_cancellation(reason: "あ" * described_class::MAX_REASON_LENGTH)).to be_success
  end

  describe "取消依頼の読み取り" do
    it "発注 ID ごとに依頼を古い順に返し、回答待ちが無くなれば取消依頼中でなくなる" do
      other = Tenancy.with_tenant(buyer.id) { FactoryBot.create(:purchase_order) }
      request_cancellation
      Tenancy.with_tenant(buyer.id) { requests.sole.update!(outcome: "rejected", decided_at: Time.current) }
      request_cancellation

      values = Tenancy.with_tenant(buyer.id) { Purchasing::PurchaseOrders.cancellation_requests_for(actor, [ order.id, other.id ]) }
      expect(values.transform_values { |list| list.map(&:outcome) }).to eq(order.id => [ :rejected, nil ], other.id => [])
      expect(find_order.cancellation_pending).to be(true)

      Tenancy.with_tenant(buyer.id) { requests.last.update!(outcome: "approved", decided_at: Time.current) }
      expect(find_order.cancellation_pending).to be(false)
    end
  end
end
