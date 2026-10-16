require "rails_helper"

# 取消の審査の承認と却下。承認は引当の解除と受注の取消を同じトランザクションで行い、引当が消費済みなら CONFLICT にする。
# 決着済みの審査は承認も却下もできない。失敗は書き込みもイベントも残さない（docs/architecture/context-map.md「取消の流れ」3、
# docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
RSpec.describe Sales::CancellationReviews do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:buyer) { FactoryBot.create(:tenant) }

  around { |example| TenantExample.run(example, supplier.id) }

  let(:user) { FactoryBot.create(:user) }
  let(:actor) { Partnerships::Actor.new(user_id: user.id, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:item) { FactoryBot.create(:item) }
  let(:order) do
    FactoryBot.create(:sales_order, customer_tenant_id: buyer.id).tap do |order|
      [ 3, 2 ].each { FactoryBot.create(:sales_order_line, :matched, sales_order: order, item_id: item.id, quantity: _1) }
    end
  end
  let!(:review) { FactoryBot.create(:cancellation_review, sales_order: order) }

  let(:published) { [] }

  before { allow(Contracts).to receive(:publish).and_wrap_original { |original, event| published << event; original.call(event) } }

  def allocate(quantity)
    Inventory::Adjustment.adjust(actor, item_id: item.id, type: "inbound", quantity:)
    Sales::OrderAllocation.allocate(actor, sales_order_id: order.id)
    published.clear
  end

  def allocated_quantities = Sales::SalesOrders.lines_for(actor, [ order.id ]).fetch(order.id).map(&:allocated_quantity)

  def stock = Inventory::Stocks.for_items(actor, [ item.id ]).fetch(item.id)

  def approve(id = review.id) = described_class.approve(actor, cancellation_review_id: id)

  def reject(id = review.id) = described_class.reject(actor, cancellation_review_id: id)

  def failure_codes(result) = result.failures.map(&:code)

  describe ".approve" do
    it "引当を解除して受注を取消済にし、審査を承認で決着させ、「取消承認」だけを出す" do
      allocate(5)

      result = approve

      expect(result.value).to have_attributes(id: order.id, status: :cancelled, cancellation_review_pending: false)
      expect(allocated_quantities).to eq([ 0, 0 ])
      expect(stock).to have_attributes(on_hand: 5, allocated: 0)
      expect(review.reload).to have_attributes(decision: "approved", decided_at: be_present, decided_by_user_id: user.id)
      # 出荷依頼の取消済は、出荷が受注の取消から導出するので、出荷へは何も出さない
      expect(published.sole).to have_attributes(class: Contracts::CancellationApproved,
        cancellation_request_id: review.source_cancellation_request_id, purchase_order_id: order.source_purchase_order_id,
        buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id, occurred_at: review.decided_at.iso8601(6))
    end

    it "全量を引き当てていない受注も、引当を解除して取り消す" do
      allocate(4)

      expect(approve.value.status).to eq(:cancelled)
      expect(stock).to have_attributes(on_hand: 4, allocated: 0)
    end

    it "引当が消費済み（出荷の計上が先に成立した）なら CONFLICT で、引当も受注も審査も変えず、イベントを出さない" do
      allocate(5)
      Inventory::Allocation.consume(actor, order.lines.map(&:id))

      expect(failure_codes(approve)).to eq([ :conflict ])
      expect(order.reload.cancelled_at).to be_nil
      expect(review.reload.decision).to be_nil
      expect(stock).to have_attributes(on_hand: 0, allocated: 0)
      expect(published).to be_empty
    end

    it "出荷済の受注の審査は CONFLICT" do
      order.update!(shipped_at: Time.current)

      expect(failure_codes(approve)).to eq([ :conflict ])
      expect(review.reload.decision).to be_nil
      expect(published).to be_empty
    end
  end

  describe ".reject" do
    it "審査を却下で決着させ、「取消却下」だけを出す。引当と受注の状況は変えない" do
      allocate(5)

      result = reject

      expect(result.value).to have_attributes(id: order.id, status: :allocated, cancellation_review_pending: false)
      expect(allocated_quantities).to eq([ 3, 2 ])
      expect(review.reload).to have_attributes(decision: "rejected", decided_at: be_present, decided_by_user_id: user.id)
      # 出荷依頼の出荷停止中は、出荷が未決の審査から導出するので、出荷へは何も出さない
      expect(published.sole).to have_attributes(class: Contracts::CancellationRejected,
        cancellation_request_id: review.source_cancellation_request_id, purchase_order_id: order.source_purchase_order_id,
        buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id, occurred_at: review.decided_at.iso8601(6))
    end
  end

  { "承認" => :approve, "却下" => :reject }.each do |name, operation|
    describe "#{name}の失敗" do
      %w[approved rejected].each do |decision|
        it "#{decision} で決着済みの審査は CONFLICT で、決着を変えずイベントを出さない" do
          review.update!(decision:, decided_at: 1.day.ago)

          expect(failure_codes(send(operation))).to eq([ :conflict ])
          expect(review.reload.decision).to eq(decision)
          expect(order.reload.cancelled_at).to be_nil
          expect(published).to be_empty
        end
      end

      # 他社の審査の ID は、入口の行列（spec/matrix）と S1 が確かめる
      it "無い審査は NOT_FOUND" do
        expect(send(operation, SecureRandom.uuid).failures.map { [ _1.code, _1.path ] })
          .to eq([ [ :not_found, [ :cancellation_review_id ] ] ])
      end
    end
  end

  describe "審査の読み取り" do
    it "受注 ID ごとに審査を古い順に返し、審査中が無くなれば取消審査中でなくなる" do
      other = FactoryBot.create(:sales_order)
      expect(Sales::SalesOrders.find(actor, order.id).cancellation_review_pending).to be(true)

      reject
      later = FactoryBot.create(:cancellation_review, sales_order: order)

      values = described_class.for_sales_orders(actor, [ order.id, other.id ])
      expect(values.transform_values { |list| list.map { [ _1.id, _1.decision ] } })
        .to eq(order.id => [ [ review.id, :rejected ], [ later.id, nil ] ], other.id => [])
      expect(described_class.find(actor, later.id)).to have_attributes(id: later.id, sales_order_id: order.id, decision: nil)

      described_class.reject(actor, cancellation_review_id: later.id)
      expect(Sales::SalesOrders.find(actor, order.id).cancellation_review_pending).to be(false)
    end
  end
end
