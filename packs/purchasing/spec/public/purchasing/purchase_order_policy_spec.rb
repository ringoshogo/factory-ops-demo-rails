require "rails_helper"

# 発注の操作の規則。取消依頼と検収は、取引を取り消す操作と金額を確定させる操作なので自社の admin に限り、
# 発注の登録は役割を問わない（docs/architecture/context-map.md「自社の中の役割」、docs/architecture/graphql-schema.md「役割による制限」）
RSpec.describe Purchasing::PurchaseOrderPolicy do
  let(:tenant_id) { SecureRandom.uuid }
  # 取消依頼は発注に対して、検収は入荷に対して評価する
  let(:targets) do
    {
      request_cancellation?: Purchasing::PurchaseOrderValue.new(id: SecureRandom.uuid, owner_tenant_id: tenant_id, order_no: "PO-000001",
        supplier_tenant_id: SecureRandom.uuid, order_date: Date.current, desired_delivery_on: nil, status: :ordered,
        cancellation_pending: false),
      inspect_receipt?: Purchasing::InboundShipmentValue.new(id: SecureRandom.uuid, owner_tenant_id: tenant_id,
        purchase_order_id: SecureRandom.uuid, shipped_on: Date.current)
    }
  end

  def actor(role) = Partnerships::Actor.new(user_id: SecureRandom.uuid, tenant_id:, name: "", email: "", role:, partner_code: "")

  def allowed?(rule, role, record = actor(role)) = described_class.new(record, user: actor(role)).apply(rule)

  %i[request_cancellation? inspect_receipt?].each do |rule|
    it "#{rule} は自社の対象について、admin には真、member には偽を返す" do
      expect(allowed?(rule, "admin", targets.fetch(rule))).to be(true)
      expect(allowed?(rule, "member", targets.fetch(rule))).to be(false)
    end

    it "#{rule} は admin でも、他社の対象には偽を返す" do
      expect(allowed?(rule, "admin", targets.fetch(rule).with(owner_tenant_id: SecureRandom.uuid))).to be(false)
    end
  end

  it "発注の登録は、member にも真を返す" do
    expect(allowed?(:place?, "member")).to be(true)
  end
end
