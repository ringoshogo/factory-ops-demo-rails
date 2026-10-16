require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

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

  # 出荷依頼の取消済は、受注の取消から導出する
  def cancel_order(request) = expect(Sales::OrderCancellation.cancel(actor.with(role: "admin"), sales_order_id: request.sales_order_id)).to be_success

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
        FactoryBot.create(:cancellation_review, sales_order_id: held.sales_order_id)
        FactoryBot.create(:shipment, shipping_instruction: FactoryBot.create(:shipping_instruction, shipment_request: shipped))
        cancel_order(cancelled)
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

      expect(list_ids(order_by: [ { field: :due_date, direction: :asc } ])).to eq([ [ d, b, c, a ].map(&:id), 4 ])
      expect(list_ids(order_by: [ { field: :due_date, direction: :desc } ])).to eq([ [ c, b, d, a ].map(&:id), 4 ])
      # 対照：並べ替えを省くと、作った順の新しいものから
      expect(list_ids).to eq([ [ d, c, b, a ].map(&:id), 4 ])
    end

    it "得意先の名前と、業務の進み順の状況で並べる" do
      beta, alpha = %w[beta alpha].map { FactoryBot.create(:tenant, name: _1) }
      a, b, c = Tenancy.with_tenant(supplier.id) do
        [ beta, alpha, beta ].map { FactoryBot.create(:shipment_request, buyer_tenant_id: _1.id) }.tap do |(cancelled, instructed, _ready)|
          cancel_order(cancelled)
          FactoryBot.create(:shipping_instruction, shipment_request: instructed)
        end
      end

      expect(list_ids(order_by: [ { field: :customer_name, direction: :asc } ])).to eq([ [ b, a, c ].map(&:id), 3 ])
      expect(list_ids(order_by: [ { field: :status, direction: :asc } ])).to eq([ [ c, b, a ].map(&:id), 3 ])
      expect(list_ids(order_by: [ { field: :status, direction: :desc } ])).to eq([ [ a, b, c ].map(&:id), 3 ])
    end

    it "受注番号の写しで並べ、写しの空の出荷依頼を向きによらず最後に置く" do
      a, b, c = Tenancy.with_tenant(supplier.id) { [ "SO-000002", nil, "SO-000001" ].map { FactoryBot.create(:shipment_request, sales_order_no: _1) } }

      expect(list_ids(order_by: [ { field: :order_no, direction: :asc } ])).to eq([ [ c, a, b ].map(&:id), 3 ])
      expect(list_ids(order_by: [ { field: :order_no, direction: :desc } ])).to eq([ [ a, c, b ].map(&:id), 3 ])
    end

    # 取り消した出荷指示は、有効な指示と同じ出荷依頼に残る。有効な指示だけを引かなければ、2 行が当たって SQL のエラーになるか、
    # 取り消した指示の日で並ぶ
    it "有効な出荷指示の出荷予定日で並べ、取り消した指示を使わず、有効な指示の無い出荷依頼を最後に置く" do
      a, b, c = Tenancy.with_tenant(supplier.id) do
        requests = Array.new(3) { FactoryBot.create(:shipment_request) }
        FactoryBot.create(:shipping_instruction, shipment_request: requests[0], planned_date: today + 5)
        FactoryBot.create(:shipping_instruction, shipment_request: requests[1], planned_date: today + 1, status: "cancelled")
        FactoryBot.create(:shipping_instruction, shipment_request: requests[1], planned_date: today + 9)
        FactoryBot.create(:shipping_instruction, shipment_request: requests[2], planned_date: today, status: "cancelled")
        requests
      end

      expect(list_ids(order_by: [ { field: :planned_date, direction: :asc } ])).to eq([ [ a, b, c ].map(&:id), 3 ])
      expect(list_ids(order_by: [ { field: :planned_date, direction: :desc } ])).to eq([ [ b, a, c ].map(&:id), 3 ])
    end

    # 受注は出荷に依存しないので、受注の取消は出荷指示を書き換えず、出荷指示の行は active のまま残る。読む側が取消済の受注の分を除く
    it "取消済の受注の出荷依頼に残った出荷指示を、出荷指示の読み込みは返さず、出荷予定日で並べると予定日の無い出荷依頼と同じ位置に並べる" do
      cancelled, instructed, bare = Tenancy.with_tenant(supplier.id) do
        Array.new(3) { FactoryBot.create(:shipment_request) }.tap do |(cancelled, instructed, _bare)|
          FactoryBot.create(:shipping_instruction, shipment_request: cancelled, planned_date: today + 1)
          FactoryBot.create(:shipping_instruction, shipment_request: instructed, planned_date: today + 5)
          cancel_order(cancelled)
        end
      end

      instructions = Tenancy.with_tenant(supplier.id) { described_class.instructions_for(actor, [ cancelled.id, instructed.id, bare.id ]) }
      # 対照：取り消していない受注の出荷依頼の指示は返り、予定日の位置に並ぶ
      expect(instructions.transform_values(&:planned_date)).to eq(instructed.id => today + 5)
      expect(list_ids(order_by: [ { field: :planned_date, direction: :asc } ])).to eq([ [ instructed, cancelled, bare ].map(&:id), 3 ])
      expect(list_ids(order_by: [ { field: :planned_date, direction: :desc } ])).to eq([ [ instructed, bare, cancelled ].map(&:id), 3 ])
    end

    # 受注の副問い合わせに行が無いと、取消済かは NULL になる。除く条件の NOT が NULL で行を落とさず、取消済でない側に倒れる
    it "受注の見えない出荷依頼の有効な出荷指示は、読み込みが返し、出荷予定日の位置に並べる" do
      orphan, bare = Tenancy.with_tenant(supplier.id) do
        [ FactoryBot.create(:shipment_request, sales_order_id: SecureRandom.uuid), FactoryBot.create(:shipment_request) ].tap do |(orphan, _bare)|
          FactoryBot.create(:shipping_instruction, shipment_request: orphan, planned_date: today + 2)
        end
      end

      instructions = Tenancy.with_tenant(supplier.id) { described_class.instructions_for(actor, [ orphan.id, bare.id ]) }
      expect(instructions.transform_values(&:planned_date)).to eq(orphan.id => today + 2)
      expect(list_ids(order_by: [ { field: :planned_date, direction: :desc } ])).to eq([ [ orphan, bare ].map(&:id), 2 ])
    end
  end

  # 出荷依頼の受注番号の写しを作り直すタスクが、受注の公開 API の組を渡す（docs/adr/011）
  describe ".put_order_numbers" do
    def put(order_numbers) = Tenancy.with_tenant(supplier.id) { described_class.put_order_numbers(order_numbers) }

    def numbers_of(tenant) = Tenancy.with_tenant(tenant.id) { Fulfillment::ShipmentRequest.pluck(:sales_order_id, :sales_order_no).to_h }

    it "受注番号の違う出荷依頼だけを書き直し、書き直した数を返す。値の同じ写しと、組に無い出荷依頼は変えない" do
      blank, same, stale, absent = Tenancy.with_tenant(supplier.id) do
        [ nil, "SO-000002", "SO-000099", "SO-000004" ].map { FactoryBot.create(:shipment_request, sales_order_no: _1) }
      end
      written_at = Tenancy.with_tenant(supplier.id) { same.reload.updated_at }

      expect(put(blank.sales_order_id => "SO-000001", same.sales_order_id => "SO-000002", stale.sales_order_id => "SO-000003",
        SecureRandom.uuid => "SO-000005")).to eq(2)
      expect(numbers_of(supplier)).to eq(blank.sales_order_id => "SO-000001", same.sales_order_id => "SO-000002",
        stale.sales_order_id => "SO-000003", absent.sales_order_id => "SO-000004")
      expect(Tenancy.with_tenant(supplier.id) { same.reload.updated_at }).to eq(written_at)
      expect(put(blank.sales_order_id => "SO-000001")).to eq(0)
      expect(put({})).to eq(0)
    end

    it "テナントの設定の外では例外にする" do
      expect { described_class.put_order_numbers(SecureRandom.uuid => "SO-000001") }.to raise_error(Tenancy::MissingTenant)
    end

    # RLS が他社の出荷依頼を隠すので、所有の条件を外しても上の example は落ちない。出荷依頼の受注 ID はテナントをまたいで一意なので、
    # 正しい組からは他社の行に当たらない。組の誤り（別のテナントの組を渡すこと）に対して、他社の出荷依頼を書かないことを確かめる
    describe "RLS の SELECT と UPDATE を開いたとき" do
      include_context "RLS の SELECT と UPDATE を開く"

      it "組に他社の出荷依頼の受注 ID が混ざっても、他社の出荷依頼を所有の列を含めて変えず、書き直した数に数えない" do
        own = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:shipment_request) }
        theirs = Tenancy.with_tenant(other.id) { FactoryBot.create(:shipment_request, sales_order_no: "SO-000007") }

        Tenancy.with_tenant(supplier.id) do
          cross_read!
          # 対照：開いた後は他社の出荷依頼が見え、自社の出荷依頼は書き直す
          before = reread(theirs)
          expect(Fulfillment::ShipmentRequest.where(id: [ own.id, theirs.id ]).pluck(:id)).to contain_exactly(own.id, theirs.id)

          expect(described_class.put_order_numbers(own.sales_order_id => "SO-000001", theirs.sales_order_id => "SO-000002")).to eq(1)
          expect(own.reload.sales_order_no).to eq("SO-000001")
          expect(reread(theirs)).to eq(before)
        end
      end
    end
  end
end
