require "rails_helper"
require_relative "../../../../../spec/support/concurrency"

# 受注側の取消と、同じ受注への「取消依頼」の受け手を 2 つの接続で同時に動かしても、受注の行ロックで直列になる。
# 取消は受注のロックを取ってから未決の審査を読むので、審査中の受注を取り消さず、取り消した受注に審査を作らない
# （docs/architecture/context-map.md「取消の流れ」）
RSpec.describe Sales::OrderCancellation do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:order) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:sales_order, customer_tenant_id: buyer.id).tap { FactoryBot.create(:sales_order_line, :matched, sales_order: _1) }
    end
  end

  after do
    delete_owned_rows([ supplier.id, buyer.id ], %w[cancellation_reviews sales_order_lines sales_orders items])
  end

  def cancel = described_class.cancel(actor, sales_order_id: order.id)

  def receive_request
    Sales::PurchasingEventReceiver.handle(Contracts::CancellationRequested.new(cancellation_request_id: SecureRandom.uuid,
      purchase_order_id: order.source_purchase_order_id, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id,
      requested_at: Time.current.iso8601(6)))
  end

  def events(pattern)
    SolidQueue::Job.where(class_name: "Contracts::EventJob").map { _1.arguments.fetch("arguments").first }.grep(pattern)
  end

  def reviews_and_cancelled_at
    Tenancy.with_tenant(supplier.id) { [ order.cancellation_reviews.pluck(:decision), order.reload.cancelled_at.present? ] }
  end

  it "取消依頼の受け手がコミットするまで取消は待ち、コミットの後は審査中の受注として CONFLICT になる" do
    _, release, receiver = hold_open(supplier.id) { receive_request }

    canceller = in_thread(supplier.id) { cancel }
    expect(blocked_on_lock?(canceller, by: receiver)).to be(true)

    commit(release, receiver)
    expect(finish(canceller).failures.map(&:code)).to eq([ :conflict ])
    expect(reviews_and_cancelled_at).to eq([ [ nil ], false ])
    expect(events(/SalesOrderCancelled|ShipmentCancelled/)).to be_empty
  end

  # 受け手が受注のロックを取らないと、取消のコミット前の受注（取消前）を読み、取り消した受注に審査中の審査を作る
  it "取消がコミットするまで取消依頼の受け手は待ち、コミットの後は取消済の受注として自動で却下する" do
    cancelled, release, canceller = hold_open(supplier.id) { cancel }
    expect(cancelled).to be_success

    receiver = in_thread(supplier.id) { receive_request }
    expect(blocked_on_lock?(receiver, by: canceller)).to be(true)

    commit(release, canceller)
    finish(receiver)
    expect(reviews_and_cancelled_at).to eq([ [], true ])
    expect(events(/CancellationRejected|ShippingHeld/)).to eq([ "Contracts::CancellationRejected" ])
  end
end
