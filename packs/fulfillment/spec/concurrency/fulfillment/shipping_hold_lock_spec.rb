require "rails_helper"

# 出荷依頼がまだ無い受注への「出荷停止」の受け手が、出荷依頼の無いことを読んでからコミットするまでの間に、
# 「出荷可能」の受け手と出荷指示の作成が割り込んでも、停止中の受注に有効な出荷指示が残らない。
# 停止の受け手と出荷可能の受け手は、受注 ID ごとのアドバイザリロックで直列になる（docs/architecture/data-model.md「出荷（`fulfillment`）」）。
# ロックの無い経路なので、ただ同時に流すと割り込むかどうかが毎回変わる。停止の受け手を開いたままにして、決まった順で割り込ませる
RSpec.describe Fulfillment::SalesEventReceiver do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:sales_order_id) { SecureRandom.uuid }
  let(:held) do
    Contracts::ShippingHeld.new(cancellation_review_id: SecureRandom.uuid, sales_order_id:, supplier_tenant_id: supplier.id)
  end
  let(:ready) do
    Contracts::SalesOrderReadyForShipment.new(sales_order_id:, sales_order_no: "SO-000042", supplier_tenant_id: supplier.id, buyer_tenant_id: buyer.id,
      purchase_order_id: SecureRandom.uuid, due_date: "2026-10-31",
      lines: [ { "sales_order_line_id" => SecureRandom.uuid, "purchase_order_line_id" => SecureRandom.uuid,
        "item_id" => SecureRandom.uuid, "quantity" => 4 } ])
  end

  after do
    delete_owned_rows([ supplier.id, buyer.id ], %w[shipping_instructions shipping_holds shipment_request_lines shipment_requests])
  end

  def request_id = Tenancy.with_tenant(supplier.id) { Fulfillment::ShipmentRequest.find_by(sales_order_id:)&.id }

  def create_instruction(id)
    Fulfillment::Instructions.create(actor, shipment_request_id: id, planned_date: Date.new(2026, 10, 20))
  end

  def outcome
    Tenancy.with_tenant(supplier.id) do
      { held: Fulfillment::ShippingHold.active.exists?(sales_order_id:),
        active_instructions: Fulfillment::ShippingInstruction.active.where(shipment_request_id: request_id).count }
    end
  end

  it "停止の受け手がコミットするまで出荷可能の受け手は待ち、コミットの後の出荷指示の作成は CONFLICT になる" do
    _, release, holder = hold_open(supplier.id) { described_class.handle(held) }

    creator = in_thread(supplier.id) { described_class.handle(ready) }
    expect(blocked_on_lock?(creator, by: holder)).to be(true)
    # 停止のコミットの前は、出荷依頼がまだできていないので、出荷指示を作る対象が無い
    expect(request_id).to be_nil

    commit(release, holder)
    finish(creator)
    expect(request_id).to be_present
    expect(Tenancy.with_tenant(supplier.id) { create_instruction(request_id) }.failures.map(&:code)).to eq([ :conflict ])
    expect(outcome).to eq(held: true, active_instructions: 0)
  end
end
