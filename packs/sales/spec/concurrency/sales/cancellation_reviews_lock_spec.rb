require "rails_helper"
require_relative "../../../../../spec/support/concurrency"

# 同じ受注の審査の決着と「取消依頼」の受け手を 2 つの接続で同時に動かしても、受注の行ロックで直列になる。
# 同じ審査の決着は一方だけが成立し、決着のイベントは 1 回だけ出る（docs/architecture/context-map.md「取消の流れ」3）
RSpec.describe Sales::CancellationReviews do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:order) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:sales_order, customer_tenant_id: buyer.id).tap { FactoryBot.create(:sales_order_line, :matched, sales_order: _1) }
    end
  end
  let!(:review) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:cancellation_review, sales_order: order) } }

  after do
    delete_owned_rows([ supplier.id, buyer.id ], %w[cancellation_reviews sales_order_lines sales_orders items])
  end

  def reject = described_class.reject(actor, cancellation_review_id: review.id)
  def approve = described_class.approve(actor, cancellation_review_id: review.id)

  def decision_events
    SolidQueue::Job.where(class_name: "Contracts::EventJob").map { _1.arguments.fetch("arguments").first }
      .grep(/Cancellation(Approved|Rejected)|ShippingHoldReleased|ShipmentCancelled/)
  end

  it "同じ審査の決着が同時に来ると、後の決着は先の決着のコミットを待ち、CONFLICT になる。決着のイベントは 1 回分だけ出る" do
    rejected, release, rejecter = hold_open(supplier.id) { reject }
    expect(rejected).to be_success

    approver = in_thread(supplier.id) { approve }
    expect(blocked_on_lock?(approver, by: rejecter)).to be(true)

    commit(release, rejecter)
    expect(finish(approver).failures.map(&:code)).to eq([ :conflict ])
    expect(Tenancy.with_tenant(supplier.id) { [ review.reload.decision, order.reload.cancelled_at ] }).to eq([ "rejected", nil ])
    expect(decision_events).to contain_exactly("Contracts::CancellationRejected", "Contracts::ShippingHoldReleased")
  end

  # 受け手が受注のロックを取らないと、承認のコミット前の受注（取消前）を読み、取り消した受注に審査中の審査を作る
  it "承認がコミットするまで同じ受注への「取消依頼」の受け手は待ち、コミットの後は取消済の受注として自動で却下する" do
    _, release, approver = hold_open(supplier.id) { approve }

    requested = Contracts::CancellationRequested.new(cancellation_request_id: SecureRandom.uuid,
      purchase_order_id: order.source_purchase_order_id, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id,
      requested_at: Time.current.iso8601(6))
    receiver = in_thread(supplier.id) { Sales::PurchasingEventReceiver.handle(requested) }
    expect(blocked_on_lock?(receiver, by: approver)).to be(true)

    commit(release, approver)
    finish(receiver)
    expect(Tenancy.with_tenant(supplier.id) { order.cancellation_reviews.pluck(:decision) }).to eq([ "approved" ])
    expect(decision_events).to include("Contracts::CancellationRejected")
  end
end
