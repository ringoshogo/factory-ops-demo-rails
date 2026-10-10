require "rails_helper"

# 出荷指示（docs/architecture/data-model.md「出荷（`fulfillment`）」）。有効な出荷指示は出荷依頼ごとに 1 件
RSpec.describe Fulfillment::Instructions do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:request) { FactoryBot.create(:shipment_request) }

  around { |example| Tenancy.with_tenant(supplier.id) { example.run } }

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

  it "取消済・出荷済の出荷依頼には指示を作れず、出荷済みの指示は取り消せない" do
    shipped = FactoryBot.create(:shipment).shipment_request

    expect(codes(described_class.create(actor, shipment_request_id: shipped.id, planned_date: Date.current))).to eq([ :conflict ])
    expect(codes(described_class.cancel(actor, shipment_request_id: shipped.id))).to eq([ :conflict ])
    request.update!(cancelled_at: Time.current)
    expect(codes(create)).to eq([ :conflict ])
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
