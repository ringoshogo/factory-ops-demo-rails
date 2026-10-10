require "rails_helper"

# 読む経路 3（docs/architecture/graphql-schema.md「発注側の視点」、docs/architecture/data-model.md「RLS」）
RSpec.describe Fulfillment::PartnerShipments do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:buyer) { FactoryBot.create(:tenant) }
  let(:purchase_order_id) { SecureRandom.uuid }
  let(:purchase_order_line_id) { SecureRandom.uuid }
  let!(:partnership) do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[view_shipments]) }
  end
  let!(:shipment) do
    Tenancy.with_tenant(supplier.id) do
      request = FactoryBot.create(:shipment_request, buyer_tenant_id: buyer.id, source_purchase_order_id: purchase_order_id)
      FactoryBot.create(:shipment, shipping_instruction: FactoryBot.create(:shipping_instruction, shipment_request: request),
        shipped_on: Date.new(2026, 10, 9)).tap do |shipment|
        FactoryBot.create(:shipment_line, shipment:, quantity: 3, shipment_request_line: FactoryBot.create(:shipment_request_line,
          shipment_request: request, source_purchase_order_line_id: purchase_order_line_id, quantity: 3))
      end
    end
  end

  def actor_of(tenant) = Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "")

  def shipments_for(tenant, ids = [ purchase_order_id ])
    Tenancy.with_tenant(tenant.id) { described_class.for_purchase_orders(actor_of(tenant), ids) }
  end

  def change_partnership(&)
    Tenancy.with_tenant(supplier.id) { yield partnership }
  end

  # 一覧のテストの規則で、発注を 2 件渡す（docs/architecture/graphql-schema.md「ページングと N+1」）
  it "自社の発注に連結した出荷を、発注ごとに、出荷実績 ID の無い値で返す" do
    other_order_id = SecureRandom.uuid
    other_line_id = SecureRandom.uuid
    Tenancy.with_tenant(supplier.id) do
      request = FactoryBot.create(:shipment_request, buyer_tenant_id: buyer.id, source_purchase_order_id: other_order_id)
      shipment = FactoryBot.create(:shipment, shipping_instruction: FactoryBot.create(:shipping_instruction, shipment_request: request),
        shipped_on: Date.new(2026, 10, 10))
      FactoryBot.create(:shipment_line, shipment:, quantity: 5, shipment_request_line: FactoryBot.create(:shipment_request_line,
        shipment_request: request, source_purchase_order_line_id: other_line_id, quantity: 5))
    end

    expect(shipments_for(buyer, [ purchase_order_id, other_order_id ])).to eq(
      purchase_order_id => [
        Fulfillment::PartnerShipmentValue.new(supplier_tenant_id: supplier.id, purchase_order_id:, shipped_on: Date.new(2026, 10, 9),
          lines: [ Fulfillment::PartnerShipmentLineValue.new(supplier_tenant_id: supplier.id, purchase_order_line_id:, quantity: 3) ])
      ],
      other_order_id => [
        Fulfillment::PartnerShipmentValue.new(supplier_tenant_id: supplier.id, purchase_order_id: other_order_id,
          shipped_on: Date.new(2026, 10, 10),
          lines: [ Fulfillment::PartnerShipmentLineValue.new(supplier_tenant_id: supplier.id, purchase_order_line_id: other_line_id,
            quantity: 5) ])
      ]
    )
    expect(Fulfillment::PartnerShipmentValue.members + Fulfillment::PartnerShipmentLineValue.members).not_to include(:id, :shipment_id)
  end

  it "view_shipments の付与が無ければ空" do
    change_partnership { _1.grants.destroy_all }

    expect(shipments_for(buyer)).to eq(purchase_order_id => [])
  end

  it "付与があっても、取引関係が失効すれば空" do
    change_partnership { _1.update!(status: "revoked", revoked_at: Time.current) }

    expect(shipments_for(buyer)).to eq(purchase_order_id => [])
  end

  it "他社の発注の ID を渡しても、出荷の発注側テナントが自社でなければ返さない" do
    other = FactoryBot.create(:tenant)
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: other.id, permissions: %w[view_shipments]) }

    expect(shipments_for(other)).to eq(purchase_order_id => [])
  end

  it "受注側の操作者が自社の出荷を引いても、発注側としての経路なので返さない" do
    expect(shipments_for(supplier)).to eq(purchase_order_id => [])
  end
end
