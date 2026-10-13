require "rails_helper"

# ダッシュボードの出荷期限。出荷待ち・出荷指示済・出荷停止中の出荷依頼のうち、期限が今日から指定の日数後以下のものを、
# 期限を過ぎたものも含めて期限の昇順で返す（docs/architecture/graphql-schema.md「読み取りの一覧」）
RSpec.describe Fulfillment::ShipmentRequests do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:today) { Date.new(2026, 10, 12) }

  def request(due_in, tenant: supplier)
    Tenancy.with_tenant(tenant.id) { FactoryBot.create(:shipment_request, due_date: due_in && today + due_in) }
  end

  def due_within = Tenancy.with_tenant(supplier.id) { described_class.due_within(actor, today:, days: 7) }

  describe ".due_within" do
    it "期限が今日から 7 日後の出荷依頼と、期限を過ぎた出荷依頼を、期限の昇順で返す。8 日後と期限の無いものは返さない" do
      seventh, overdue, today_due = request(7), request(-3), request(0)
      request(8)
      request(nil)

      expect(due_within.map(&:id)).to eq([ overdue.id, today_due.id, seventh.id ])
    end

    it "出荷待ち・出荷指示済・出荷停止中を返し、出荷済と取消済を返さない" do
      ready, instructed, held, shipped, cancelled = Array.new(5) { request(1) }
      Tenancy.with_tenant(supplier.id) do
        FactoryBot.create(:shipping_instruction, shipment_request: instructed)
        FactoryBot.create(:shipping_hold, sales_order_id: held.sales_order_id)
        FactoryBot.create(:shipment, shipping_instruction: FactoryBot.create(:shipping_instruction, shipment_request: shipped))
        cancelled.update!(cancelled_at: Time.current)
      end

      expect(due_within.to_h { [ _1.id, _1.status ] }).to eq(ready.id => :ready, instructed.id => :instructed, held.id => :on_hold)
    end

    it "他社の出荷依頼を返さない" do
      own = request(1)
      request(1, tenant: other)

      # 対照：同じ期限の自社の出荷依頼は返る
      expect(due_within.map(&:id)).to eq([ own.id ])
    end

    it "上限の件数までを、期限の早いものから返す" do
      stub_const("#{described_class}::DUE_WITHIN_LIMIT", 2)
      later, earliest, middle = request(3), request(1), request(2)

      expect(due_within.map(&:id)).to eq([ earliest.id, middle.id ])
      expect(later.id).not_to be_in(due_within.map(&:id))
    end
  end

  # 一覧の並べ替え（docs/architecture/graphql-schema.md「ページングと N+1」）
  describe ".list" do
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

    it "出荷期限と ID の組で並べ、期限の無い出荷依頼を向きによらず最後に置く。件数は他社の出荷依頼を数えない" do
      a, b, c, d = [ nil, 3, 3, 1 ].map { request(_1) }
      request(1, tenant: other)

      expect(list_ids(order_by: { field: :due_date, direction: :asc })).to eq([ [ d, b, c, a ].map(&:id), 4 ])
      expect(list_ids(order_by: { field: :due_date, direction: :desc })).to eq([ [ c, b, d, a ].map(&:id), 4 ])
      # 対照：並べ替えを省くと、作った順の新しいものから
      expect(list_ids).to eq([ [ d, c, b, a ].map(&:id), 4 ])
    end
  end
end
