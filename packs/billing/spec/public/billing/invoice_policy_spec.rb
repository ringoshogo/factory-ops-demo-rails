require "rails_helper"

# 請求の操作の規則。請求条件の設定・締め・下書きの破棄・確定は、金額を確定させる操作なので自社の admin に限る
# （docs/architecture/context-map.md「自社の中の役割」、docs/architecture/graphql-schema.md「役割による制限」）
RSpec.describe Billing::InvoicePolicy do
  let(:tenant_id) { SecureRandom.uuid }
  let(:own_invoice) { Billing::InvoiceValue.new(id: SecureRandom.uuid, owner_tenant_id: tenant_id, customer_tenant_id: SecureRandom.uuid,
    invoice_number: nil, period_start: Date.current, period_end: Date.current, issued_at: nil, state: :draft, subtotal: 0, tax_total: 0, total: 0) }

  def actor(role) = Partnerships::Actor.new(user_id: SecureRandom.uuid, tenant_id:, name: "", email: "", role:, partner_code: "")

  def allowed?(rule, role, record = actor(role)) = described_class.new(record, user: actor(role)).apply(rule)

  %i[set_term? close?].each do |rule|
    it "#{rule} は対象を引かず、admin には真、member には偽を返す" do
      expect(allowed?(rule, "admin")).to be(true)
      expect(allowed?(rule, "member")).to be(false)
    end
  end

  %i[discard? issue?].each do |rule|
    it "#{rule} は自社の請求書について、admin には真、member には偽を返す" do
      expect(allowed?(rule, "admin", own_invoice)).to be(true)
      expect(allowed?(rule, "member", own_invoice)).to be(false)
    end

    it "#{rule} は admin でも、他社の請求書には偽を返す" do
      expect(allowed?(rule, "admin", own_invoice.with(owner_tenant_id: SecureRandom.uuid))).to be(false)
    end
  end
end
