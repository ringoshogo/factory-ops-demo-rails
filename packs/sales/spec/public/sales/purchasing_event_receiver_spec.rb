require "rails_helper"
require_relative "../../../../../spec/support/events"
require_relative "../../../../../spec/support/shared_examples/idempotent_receiver"

# 「取消依頼」の受注側の受け手。審査を作って出荷停止を出し、受注が出荷済みか取消済なら審査を作らずに自動で却下する
# （docs/architecture/context-map.md「取消の流れ」2・4、docs/architecture/data-model.md「イベントの受け口と冪等キー」）
RSpec.describe Sales::PurchasingEventReceiver do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:order) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:sales_order, customer_tenant_id: buyer.id).tap { FactoryBot.create(:sales_order_line, :matched, sales_order: _1) }
    end
  end
  let(:requested_at) { Time.zone.parse("2026-10-11 09:30:00.123456") }
  let(:event) do
    Contracts::CancellationRequested.new(cancellation_request_id: SecureRandom.uuid, purchase_order_id: order.source_purchase_order_id,
      buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id, requested_at: requested_at.iso8601(6))
  end

  let(:published) { [] }

  before { allow(Contracts).to receive(:publish).and_wrap_original { |original, event| published << event; original.call(event) } }

  def handle(event) = Tenancy.with_tenant(supplier.id) { described_class.handle(event) }

  def reviews = Tenancy.with_tenant(supplier.id) { Sales::CancellationReview.order(:id).to_a }

  it_behaves_like "冪等な受け手" do
    # 発注側が、自社の発注について出す
    let(:publish_event) { -> { Tenancy.with_tenant(buyer.id) { Contracts.publish(event) } } }
    let(:written_rows) { -> { reviews.size } }
  end

  it "受注側テナントの名義で審査中の審査を作り、受注を止める「出荷停止」を出す。受注は取消審査中になる" do
    handle(event)

    review = reviews.sole
    expect(review).to have_attributes(owner_tenant_id: supplier.id, sales_order_id: order.id,
      source_cancellation_request_id: event.cancellation_request_id, requested_at:, decision: nil)
    expect(published.sole).to have_attributes(class: Contracts::ShippingHeld, cancellation_review_id: review.id,
      sales_order_id: order.id, supplier_tenant_id: supplier.id)
    expect(Tenancy.with_tenant(supplier.id) { Sales::SalesOrders.find(actor, order.id) })
      .to have_attributes(status: :received, cancellation_review_pending: true)
  end

  { "出荷済" => :shipped_at, "取消済" => :cancelled_at }.each do |name, column|
    it "受注が#{name}なら、審査を作らずに「取消却下」を出す" do
      Tenancy.with_tenant(supplier.id) { order.update!(column => Time.current) }

      handle(event)

      expect(reviews).to be_empty
      expect(published.sole).to have_attributes(class: Contracts::CancellationRejected,
        cancellation_request_id: event.cancellation_request_id, purchase_order_id: event.purchase_order_id,
        buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id)
    end
  end

  it "受注がまだ無い（発注登録より先に届いた）なら、何も書かずに失敗し、再配送に任せる" do
    expect { handle(event.with(purchase_order_id: SecureRandom.uuid)) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(reviews).to be_empty
    expect(published).to be_empty
  end

  it "発注側テナントが一致しない受注は書かない" do
    expect { handle(event.with(buyer_tenant_id: FactoryBot.create(:tenant).id)) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(reviews).to be_empty
  end

  it "配送表に無い種類のイベントは、審査を書かずに ArgumentError で失敗する" do
    unexpected = Contracts::PartMatchPending.new(purchase_order_id: order.source_purchase_order_id, buyer_tenant_id: buyer.id,
      supplier_tenant_id: supplier.id)

    expect { handle(unexpected) }.to raise_error(ArgumentError, "unexpected event: Contracts::PartMatchPending")
    expect(reviews).to be_empty
  end
end
