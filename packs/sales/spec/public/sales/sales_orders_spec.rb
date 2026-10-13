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

  # 一覧を最後のページまで first 件ずつたどり、受注 ID と件数を返す
  def list_ids(first: 2, **options)
    Tenancy.with_tenant(supplier.id) do
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

  # 一覧の並べ替えと絞り込み（docs/architecture/graphql-schema.md「ページングと N+1」）
  describe ".list" do
    it "並べ替えの列ごとに、列の値と ID の組で並べ、値の無い受注を向きによらず最後に置く" do
      a, b, c, d = Tenancy.with_tenant(supplier.id) do
        [ [ "SO-000003", 2, nil ], [ "SO-000001", 3, 5 ], [ "SO-000002", 1, 5 ], [ "SO-000004", 2, 1 ] ].map do |order_no, days, due|
          FactoryBot.create(:sales_order, order_no:, order_date: Date.new(2026, 10, days), due_date: due && Date.new(2026, 11, due))
        end
      end
      Tenancy.with_tenant(other.id) { FactoryBot.create(:sales_order) }

      expect(list_ids(order_by: { field: :order_no, direction: :asc })).to eq([ [ b, c, a, d ].map(&:id), 4 ])
      expect(list_ids(order_by: { field: :order_date, direction: :desc })).to eq([ [ b, d, a, c ].map(&:id), 4 ])
      expect(list_ids(order_by: { field: :due_date, direction: :asc })).to eq([ [ d, b, c, a ].map(&:id), 4 ])
      expect(list_ids(order_by: { field: :due_date, direction: :desc })).to eq([ [ c, b, d, a ].map(&:id), 4 ])
      # 対照：並べ替えを省くと、作った順の新しいものから
      expect(list_ids).to eq([ [ d, c, b, a ].map(&:id), 4 ])
    end

    it "得意先と、両端を含む受注日の範囲で絞り、件数も同じ条件で数える。受注日の始まりが終わりより後なら空" do
      customer = FactoryBot.create(:tenant)
      hit, before_range, other_customer, last_day = Tenancy.with_tenant(supplier.id) do
        [ [ customer, 10 ], [ customer, 9 ], [ FactoryBot.create(:tenant), 10 ], [ customer, 12 ] ].map do |tenant, day|
          FactoryBot.create(:sales_order, customer_tenant_id: tenant.id, order_date: Date.new(2026, 10, day))
        end
      end
      Tenancy.with_tenant(other.id) { FactoryBot.create(:sales_order, customer_tenant_id: customer.id, order_date: Date.new(2026, 10, 10)) }
      range = { order_date_from: Date.new(2026, 10, 10), order_date_to: Date.new(2026, 10, 12) }

      expect(list_ids(filter: { customer_tenant_id: customer.id, **range })).to eq([ [ last_day.id, hit.id ], 2 ])
      expect(list_ids(filter: { customer_tenant_id: customer.id })).to eq([ [ last_day.id, before_range.id, hit.id ], 3 ])
      expect(list_ids(filter: range)).to eq([ [ last_day.id, other_customer.id, hit.id ], 3 ])
      expect(list_ids(filter: { order_date_from: Date.new(2026, 10, 12), order_date_to: Date.new(2026, 10, 10) })).to eq([ [], 0 ])
      expect(list_ids(filter: { customer_tenant_id: other.id })).to eq([ [], 0 ])
    end
  end

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

    # ダッシュボードの数と、そこから飛ぶ一覧の件数が食い違わない（docs/architecture/graphql-schema.md「読み取りの一覧」）
    it "状況ごとの件数は、その状況で絞った一覧の件数と同じ" do
      Tenancy.with_tenant(supplier.id) do
        order(cancelled_at: Time.current)
        order(shipped_at: Time.current, inspected_at: Time.current)
        order(shipped_at: Time.current)
        order(matched: false)
        order(allocated: [ 2, 2 ])
        2.times { order(allocated: [ 2, 0 ]) }
        order
      end
      Tenancy.with_tenant(other.id) { order(allocated: [ 2, 2 ]) }
      totals = Sales::SalesOrderStatus::ALL.index_with { |status| list_ids(filter: { statuses: [ status ] }).last }

      # 対照：どの状況にも受注がある
      expect(totals).to eq(cancelled: 1, inspected: 1, shipped: 1, awaiting_part_match: 1, allocated: 1, partially_allocated: 2, received: 1)
      expect(count_by_status).to eq(totals)
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
