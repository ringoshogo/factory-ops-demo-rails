require "rails_helper"

# 発注側が自社の受領請求書と明細を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）。
# 一覧は親を 2 件以上作って読み、明細を親ごとに取り違えないことと、見えない受領請求書が空になることを確かめる
RSpec.describe Purchasing::ReceivedInvoices do
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:invoices) do
    Tenancy.with_tenant(buyer.id) do
      [ [ "INV-000001", 2 ], [ "INV-000002", 1 ] ].map do |invoice_number, line_count|
        FactoryBot.create(:received_invoice, invoice_number:).tap do |invoice|
          FactoryBot.create_list(:received_invoice_line, line_count, received_invoice: invoice)
        end
      end
    end
  end
  # 相手テナントが自社の受領請求書として持つ行。自社の一覧には混ざらない
  let!(:foreign) { Tenancy.with_tenant(FactoryBot.create(:tenant).id) { FactoryBot.create(:received_invoice_line).received_invoice } }

  def as_buyer(&) = Tenancy.with_tenant(buyer.id, &)

  it "一覧は自社の受領請求書を新しい順に返す" do
    values = as_buyer { described_class.list(actor, first: 10, after: nil).values }

    expect(values.map { [ _1.id, _1.invoice_number, _1.supplier_tenant_id ] })
      .to eq(invoices.reverse.map { [ _1.id, _1.invoice_number, _1.supplier_tenant_id ] })
  end

  it "1 件の読み取りは自社の受領請求書を返し、見えない ID と存在しない ID は nil になる" do
    expect(as_buyer { described_class.find(actor, invoices[0].id) }).to have_attributes(id: invoices[0].id, invoice_number: "INV-000001")
    expect(as_buyer { described_class.find(actor, foreign.id) }).to be_nil
    expect(as_buyer { described_class.find(actor, SecureRandom.uuid) }).to be_nil
  end

  it "明細は受領請求書ごとに返し、見えない受領請求書は空にする" do
    result = as_buyer { described_class.lines_for(actor, [ *invoices.map(&:id), foreign.id ]) }

    expected = as_buyer { invoices.to_h { |invoice| [ invoice.id, invoice.lines.order(:id).map(&:purchase_order_line_id) ] } }
    expect(result.transform_values { _1.map(&:purchase_order_line_id) }).to eq(expected.merge(foreign.id => []))
    expect(expected.values.map(&:size)).to eq([ 2, 1 ])
  end
end
