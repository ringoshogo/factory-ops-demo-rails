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

# 発注の一覧の並べ替えと絞り込み（docs/architecture/graphql-schema.md「ページングと N+1」）
RSpec.describe Purchasing::PurchaseOrders, ".list" do
  let!(:buyer) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "") }

  # 一覧を最後のページまで first 件ずつたどり、発注 ID と件数を返す
  def list_ids(first: 2, **options)
    Tenancy.with_tenant(buyer.id) do
      ids = []
      after = nil
      loop do
        page = described_class.list(actor, first:, after:, **options)
        ids.concat(page.values.map(&:id))
        break [ ids, page.total_count ] unless page.has_next_page

        after = page.cursors.last
      end
    end
  end

  it "並べ替えの列ごとに、列の値と ID の組で並べ、希望納期の無い発注を向きによらず最後に置く" do
    a, b, c, d = Tenancy.with_tenant(buyer.id) do
      [ [ "PO-000003", 2, nil ], [ "PO-000001", 3, 5 ], [ "PO-000002", 1, 5 ], [ "PO-000004", 2, 1 ] ].map do |order_no, day, desired|
        FactoryBot.create(:purchase_order, order_no:, order_date: Date.new(2026, 10, day), desired_delivery_on: desired && Date.new(2026, 11, desired))
      end
    end
    Tenancy.with_tenant(other.id) { FactoryBot.create(:purchase_order) }

    expect(list_ids(order_by: { field: :order_no, direction: :desc })).to eq([ [ d, a, c, b ].map(&:id), 4 ])
    expect(list_ids(order_by: { field: :order_date, direction: :asc })).to eq([ [ c, a, d, b ].map(&:id), 4 ])
    expect(list_ids(order_by: { field: :desired_delivery_on, direction: :asc })).to eq([ [ d, b, c, a ].map(&:id), 4 ])
    expect(list_ids(order_by: { field: :desired_delivery_on, direction: :desc })).to eq([ [ c, b, d, a ].map(&:id), 4 ])
    # 対照：並べ替えを省くと、作った順の新しいものから
    expect(list_ids).to eq([ [ d, c, b, a ].map(&:id), 4 ])
  end

  it "受注側と、両端を含む発注日の範囲で絞り、件数も同じ条件で数える。発注日の始まりが終わりより後なら空" do
    supplier = FactoryBot.create(:tenant)
    hit, before_range, other_supplier, last_day = Tenancy.with_tenant(buyer.id) do
      [ [ supplier, 10 ], [ supplier, 9 ], [ FactoryBot.create(:tenant), 10 ], [ supplier, 12 ] ].map do |tenant, day|
        FactoryBot.create(:purchase_order, supplier_tenant_id: tenant.id, order_date: Date.new(2026, 10, day))
      end
    end
    Tenancy.with_tenant(other.id) { FactoryBot.create(:purchase_order, supplier_tenant_id: supplier.id, order_date: Date.new(2026, 10, 10)) }
    range = { order_date_from: Date.new(2026, 10, 10), order_date_to: Date.new(2026, 10, 12) }

    expect(list_ids(filter: { supplier_tenant_id: supplier.id, **range })).to eq([ [ last_day.id, hit.id ], 2 ])
    expect(list_ids(filter: { supplier_tenant_id: supplier.id })).to eq([ [ last_day.id, before_range.id, hit.id ], 3 ])
    expect(list_ids(filter: range)).to eq([ [ last_day.id, other_supplier.id, hit.id ], 3 ])
    expect(list_ids(filter: { order_date_from: Date.new(2026, 10, 12), order_date_to: Date.new(2026, 10, 10) })).to eq([ [], 0 ])
  end
end
