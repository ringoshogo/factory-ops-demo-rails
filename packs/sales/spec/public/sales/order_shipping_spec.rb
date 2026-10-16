require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

# 出荷が受注を読み、受注に出荷済を書く入口。どれも Scope の自社の受注だけを読み書きする
# （docs/architecture/context-map.md「コンテキスト間の関係」、docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
RSpec.describe Sales::OrderShipping do
  include ActiveSupport::Testing::TimeHelpers

  let(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:order) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:sales_order) } }

  def statuses(ids)
    sql = described_class.status_sql(actor)
    rows = Sales::SalesOrder.lease_connection.select_rows("SELECT #{sql.columns.values_at(:sales_order_id, :cancelled, :under_review).join(', ')} " \
      "FROM (#{sql.sql}) s")
    rows.select { ids.include?(_1.first) }.to_h { [ _1.first, _1.drop(1) ] }
  end

  describe ".lock" do
    it "自社の受注の取消済と審査中を返す" do
      Tenancy.with_tenant(supplier.id) do
        cancelled = FactoryBot.create(:sales_order, cancelled_at: Time.current)
        FactoryBot.create(:cancellation_review, sales_order: order)
        decided = FactoryBot.create(:sales_order).tap do
          FactoryBot.create(:cancellation_review, sales_order: _1, decision: "rejected", decided_at: Time.current)
        end

        expect(described_class.lock(actor, order.id)).to eq(described_class::State.new(cancelled: false, under_review: true))
        expect(described_class.lock(actor, cancelled.id)).to eq(described_class::State.new(cancelled: true, under_review: false))
        expect(described_class.lock(actor, decided.id)).to eq(described_class::State.new(cancelled: false, under_review: false))
      end
    end

    it "見えない受注は nil を返す" do
      expect(Tenancy.with_tenant(supplier.id) { described_class.lock(actor, SecureRandom.uuid) }).to be_nil
    end
  end

  describe ".mark_shipped" do
    def shipped_at = Tenancy.with_tenant(supplier.id) { order.reload.shipped_at }

    it "出荷済の時刻を 1 回だけ書き、2 回目は最初の値のまま変えない" do
      expect(Tenancy.with_tenant(supplier.id) { described_class.mark_shipped(actor, order.id) }).to be_success
      first = shipped_at

      travel 1.hour do
        expect(Tenancy.with_tenant(supplier.id) { described_class.mark_shipped(actor, order.id) }).to be_success
      end

      expect(first).to be_present
      expect(shipped_at).to eq(first)
    end

    it "見えない受注には、受注 ID を指す NOT_FOUND を返す" do
      result = Tenancy.with_tenant(supplier.id) { described_class.mark_shipped(actor, SecureRandom.uuid) }

      expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :sales_order_id ] ] ])
    end
  end

  describe ".status_sql" do
    it "自社の受注ごとに、取消済か、決着していない審査があるかを返す" do
      Tenancy.with_tenant(supplier.id) do
        cancelled = FactoryBot.create(:sales_order, cancelled_at: Time.current)
        FactoryBot.create(:cancellation_review, sales_order: order)

        expect(statuses([ order.id, cancelled.id ])).to eq(order.id => [ false, true ], cancelled.id => [ true, false ])
      end
    end
  end

  # 3 つとも、出荷の公開 API を通して受注の ID を受け取る。出荷依頼は受注を ID で参照するだけなので、他社の受注の ID を持つ出荷依頼も
  # DB は拒まない。所有の条件を RLS に任せると、RLS を開いたときだけ他社の受注を読み書きする（docs/guides/testing.md「行列テストとの分担」）
  describe "RLS の SELECT と UPDATE を開いたとき" do
    include_context "RLS の SELECT と UPDATE を開く"

    let!(:theirs) do
      Tenancy.with_tenant(FactoryBot.create(:tenant).id) do
        FactoryBot.create(:sales_order).tap { FactoryBot.create(:cancellation_review, sales_order: _1) }
      end
    end
    let!(:their_cancelled) { Tenancy.with_tenant(theirs.owner_tenant_id) { FactoryBot.create(:sales_order, cancelled_at: Time.current) } }

    it "他社の受注をロックせずに nil を返し、出荷済を書かずに NOT_FOUND を返す。自社の受注には書く" do
      Tenancy.with_tenant(supplier.id) do
        cross_read!
        # 対照：開いた後は、他社の受注が見え、自社の受注には出荷済を書く
        before = reread(theirs)
        expect(described_class.lock(actor, order.id)).to be_present
        expect(described_class.mark_shipped(actor, order.id)).to be_success
        expect(order.reload.shipped_at).to be_present

        expect(described_class.lock(actor, theirs.id)).to be_nil
        expect(described_class.mark_shipped(actor, theirs.id).failures.map(&:code)).to eq([ :not_found ])
        expect(reread(theirs)).to eq(before)
      end
    end

    it "他社の受注の取消と審査を返さない" do
      Tenancy.with_tenant(supplier.id) do
        cross_read!
        # 対照：開いた後は、他社の取消済の受注と審査が見え、自社の受注は返る
        expect(Sales::SalesOrder.where(id: [ theirs.id, their_cancelled.id ]).count).to eq(2)
        expect(Sales::CancellationReview.where(sales_order_id: theirs.id).count).to eq(1)

        expect(statuses([ order.id, theirs.id, their_cancelled.id ])).to eq(order.id => [ false, false ])
      end
    end
  end
end
