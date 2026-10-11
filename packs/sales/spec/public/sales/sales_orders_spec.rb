require "rails_helper"

# ダッシュボードの受注の件数。受注一覧と同じ導出で、7 つの状況ごとに 0 件も含めて数え、取消済も数える
# （docs/architecture/graphql-schema.md「読み取りの一覧」）
RSpec.describe Sales::SalesOrders do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  # 明細 2 つの受注を作り、明細ごとに引き当てる数量を渡す。照合前の明細を混ぜるなら matched: false
  def order(allocated: [ 0, 0 ], matched: true, **attributes)
    FactoryBot.create(:sales_order, **attributes).tap do |order|
      allocated.each do |quantity|
        line = FactoryBot.create(:sales_order_line, *(matched ? [ :matched ] : []), sales_order: order, quantity: 2)
        FactoryBot.create(:allocation, sales_order_line_id: line.id, quantity:) if quantity.positive?
      end
    end
  end

  def count_by_status = Tenancy.with_tenant(supplier.id) { described_class.count_by_status(actor) }

  describe ".count_by_status" do
    it "状況ごとに数え、取消済も数える" do
      Tenancy.with_tenant(supplier.id) do
        2.times { order(cancelled_at: Time.current) }
        order(shipped_at: Time.current, inspected_at: Time.current)
        order(shipped_at: Time.current)
        order(matched: false)
        order(allocated: [ 2, 2 ])
        2.times { order(allocated: [ 2, 0 ]) }
        3.times { order }
      end

      expect(count_by_status).to eq(cancelled: 2, inspected: 1, shipped: 1, awaiting_part_match: 1, allocated: 1,
        partially_allocated: 2, received: 3)
    end

    it "受注の無い状況も 0 件で返し、他社の受注を数えない" do
      Tenancy.with_tenant(supplier.id) { order(cancelled_at: Time.current) }
      Tenancy.with_tenant(other.id) do
        2.times { order(cancelled_at: Time.current) }
        order
      end

      # 対照：自社の取消済は数える
      expect(count_by_status).to eq(cancelled: 1, inspected: 0, shipped: 0, awaiting_part_match: 0, allocated: 0,
        partially_allocated: 0, received: 0)
    end
  end
end
