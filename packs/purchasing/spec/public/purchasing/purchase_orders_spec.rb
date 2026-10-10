require "rails_helper"

# 入荷の検収と検収数量の一括取得（docs/architecture/graphql-schema.md「読み取りの一覧」）。
# 入荷を 2 件以上まとめて渡し、入荷ごとの値を取り違えないことと、見えない入荷と検収の前の入荷が空になることを確かめる
RSpec.describe Purchasing::PurchaseOrders, "の入荷の検収" do
  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "") }

  # 検収日と検収数量の違う 2 件の検収済の入荷と、検収の前の入荷 1 件
  let!(:inspected) do
    Tenancy.with_tenant(buyer.id) do
      [ [ Date.new(2026, 10, 20), 1 ], [ Date.new(2026, 10, 21), 2 ] ].map do |inspected_on, accepted_quantity|
        FactoryBot.create(:receipt_inspection_line, accepted_quantity:,
          receipt_inspection: FactoryBot.create(:receipt_inspection, inspected_on:))
      end
    end
  end
  let!(:uninspected) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:inbound_shipment_line) } }
  let!(:others) do
    Tenancy.with_tenant(FactoryBot.create(:tenant).id) { FactoryBot.create(:receipt_inspection_line).receipt_inspection.inbound_shipment_id }
  end

  let(:inbound_ids) { [ *inspected.map { _1.inbound_shipment_line.inbound_shipment_id }, uninspected.inbound_shipment_id ] }

  it "inspections_for は、検収済の入荷ごとに検収日を返し、検収の前の入荷と見えない入荷は空にする" do
    result = Tenancy.with_tenant(buyer.id) { described_class.inspections_for(actor, [ *inbound_ids, others ]) }

    expect(result.transform_values(&:inspected_on))
      .to eq(inbound_ids[0] => Date.new(2026, 10, 20), inbound_ids[1] => Date.new(2026, 10, 21))
  end

  it "inbound_shipment_lines_for は、入荷の明細ごとの検収数量を返し、検収の前の明細は空にする" do
    result = Tenancy.with_tenant(buyer.id) { described_class.inbound_shipment_lines_for(actor, inbound_ids) }

    expect(result.transform_values { |lines| lines.map(&:accepted_quantity) })
      .to eq(inbound_ids[0] => [ 1 ], inbound_ids[1] => [ 2 ], inbound_ids[2] => [ nil ])
  end
end
