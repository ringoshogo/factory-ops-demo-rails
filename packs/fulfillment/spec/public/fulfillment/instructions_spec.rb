require "rails_helper"

# 出荷指示（docs/architecture/data-model.md「出荷（`fulfillment`）」）。有効な出荷指示は出荷依頼ごとに 1 件
RSpec.describe Fulfillment::Instructions do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:request) { FactoryBot.create(:shipment_request) }

  around { |example| TenantExample.run(example, supplier.id) }

  def create = described_class.create(actor, shipment_request_id: request.id, planned_date: Date.current)
  def cancel = described_class.cancel(actor, shipment_request_id: request.id)
  def codes(result) = result.failures.map(&:code)

  it "指示を作ると出荷指示済、取り消すと出荷待ちに戻り、作り直せる" do
    expect(create.value.status).to eq(:instructed)
    expect(cancel.value.status).to eq(:ready)
    expect(create.value.status).to eq(:instructed)
  end

  it "有効な指示がある出荷依頼への 2 つ目の指示は CONFLICT で、指示は 1 件のまま" do
    create

    expect(codes(create)).to eq([ :conflict ])
    expect(request.instructions.active.count).to eq(1)
  end

  it "有効な指示が 2 件になる書き込みは、部分一意索引が拒否する" do
    FactoryBot.create(:shipping_instruction, shipment_request: request)

    expect {
      Fulfillment::ShippingInstruction.transaction(requires_new: true) { FactoryBot.create(:shipping_instruction, shipment_request: request) }
    }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { FactoryBot.create(:shipping_instruction, shipment_request: request, status: "cancelled") }.not_to raise_error
  end

  it "出荷済の出荷依頼には指示を作れず、出荷済みの指示は取り消せない" do
    shipped = FactoryBot.create(:shipment).shipment_request

    expect(codes(described_class.create(actor, shipment_request_id: shipped.id, planned_date: Date.current))).to eq([ :conflict ])
    expect(codes(described_class.cancel(actor, shipment_request_id: shipped.id))).to eq([ :conflict ])
  end

  describe "受注の取消と審査" do
    let(:admin) { actor.with(role: "admin") }

    {
      "取消済の受注" => ->(request, admin) { Sales::OrderCancellation.cancel(admin, sales_order_id: request.sales_order_id) },
      "未決の審査がある受注" => ->(request, _admin) { FactoryBot.create(:cancellation_review, sales_order_id: request.sales_order_id) }
    }.each do |name, prepare|
      it "#{name}の出荷依頼には指示を作れず CONFLICT になる" do
        prepare.call(request, admin)

        expect(codes(create)).to eq([ :conflict ])
        expect(request.instructions.count).to eq(0)
      end
    end

    def status = Fulfillment::ShipmentRequests.find(actor, request.id).status

    it "未決の審査がある受注の出荷依頼は出荷停止中になり、有効な指示を取り消しても出荷停止中のまま。審査を却下すると指示を作れる" do
      create
      review = FactoryBot.create(:cancellation_review, sales_order_id: request.sales_order_id)
      expect(status).to eq(:on_hold)

      cancel
      expect(status).to eq(:on_hold)
      expect(codes(create)).to eq([ :conflict ])
      expect(request.instructions.active.count).to eq(0)

      expect(Sales::CancellationReviews.reject(admin, cancellation_review_id: review.id)).to be_success
      expect(status).to eq(:ready)
      expect(create.value.status).to eq(:instructed)
    end

    it "別の受注の審査と、決着した審査は、指示の作成を止めない" do
      FactoryBot.create(:cancellation_review)
      FactoryBot.create(:cancellation_review, sales_order_id: request.sales_order_id, decision: "rejected", decided_at: Time.current)

      expect(create.value.status).to eq(:instructed)
    end

    # 受注を取り消しても出荷指示の行は active のまま残る。取消済の受注の出荷依頼の指示を取り消しても害は無い
    it "取消済の受注の出荷依頼に残った有効な指示は、取り消せる" do
      create
      expect(Sales::OrderCancellation.cancel(admin, sales_order_id: request.sales_order_id)).to be_success

      expect(cancel.value.status).to eq(:cancelled)
      expect(request.instructions.active.count).to eq(0)
    end
  end

  # 出荷依頼は受注を ID で参照するだけなので、受注の行の無い出荷依頼を DB は拒まない。受注の取消と審査を読めないので、指示を作らない
  it "受注の行の無い出荷依頼には指示を作らず、出荷依頼 ID を指す NOT_FOUND を返す" do
    orphan = FactoryBot.create(:shipment_request, sales_order_id: SecureRandom.uuid)
    # 対照：受注の行のある出荷依頼には作れる
    expect(create.value.status).to eq(:instructed)

    result = described_class.create(actor, shipment_request_id: orphan.id, planned_date: Date.current)

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :shipment_request_id ] ] ])
    expect(orphan.instructions.count).to eq(0)
  end

  it "有効な指示の無い出荷依頼の取消と、見えない出荷依頼は失敗する" do
    expect(codes(cancel)).to eq([ :conflict ])
    expect(codes(described_class.cancel(actor, shipment_request_id: SecureRandom.uuid))).to eq([ :not_found ])
  end

  it "見えない出荷依頼には指示を作れず、出荷依頼 ID を指す NOT_FOUND を返す" do
    result = described_class.create(actor, shipment_request_id: SecureRandom.uuid, planned_date: Date.current)

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :shipment_request_id ] ] ])
    expect(Fulfillment::ShippingInstruction.count).to eq(0)
  end
end
