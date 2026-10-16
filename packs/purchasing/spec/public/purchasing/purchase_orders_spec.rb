require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

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

    expect(list_ids(order_by: [ { field: :order_no, direction: :desc } ])).to eq([ [ d, a, c, b ].map(&:id), 4 ])
    expect(list_ids(order_by: [ { field: :order_date, direction: :asc } ])).to eq([ [ c, a, d, b ].map(&:id), 4 ])
    expect(list_ids(order_by: [ { field: :desired_delivery_on, direction: :asc } ])).to eq([ [ d, b, c, a ].map(&:id), 4 ])
    expect(list_ids(order_by: [ { field: :desired_delivery_on, direction: :desc } ])).to eq([ [ c, b, d, a ].map(&:id), 4 ])
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

  # 合計金額は明細の数量と確定した単価の積の和で、受注確定の前の明細があれば空にする。受注確定は全明細に一度に単価を写すので、
  # 単価の写しの有る明細と無い明細が混ざる発注はできないが、混ざっても一部の合計を出さないことを、混ぜた行で確かめる
  it "合計金額を持ち、合計で並べると受注確定の前の発注を向きによらず最後に置く" do
    small, unconfirmed, large = Tenancy.with_tenant(buyer.id) do
      [ [ 120 ], [ 120, nil ], [ 500, 120 ] ].map do |prices|
        FactoryBot.create(:purchase_order).tap do |order|
          prices.each do |price|
            FactoryBot.create(:purchase_order_line, purchase_order: order, quantity: 2, confirmed_unit_price: price,
              confirmed_item_name: price && "六角ボルト M8")
          end
        end
      end
    end

    values = Tenancy.with_tenant(buyer.id) { described_class.list(actor, first: 10, after: nil).values.to_h { [ _1.id, _1.total_amount ] } }
    expect(values).to eq(small.id => 240, unconfirmed.id => nil, large.id => 1240)
    expect(list_ids(order_by: [ { field: :total_amount, direction: :asc } ])).to eq([ [ small, large, unconfirmed ].map(&:id), 3 ])
    expect(list_ids(order_by: [ { field: :total_amount, direction: :desc } ])).to eq([ [ large, small, unconfirmed ].map(&:id), 3 ])
  end

  it "受注側の名前と、業務の進み順の状況で並べる" do
    beta, alpha = %w[beta alpha].map { FactoryBot.create(:tenant, name: _1) }
    a, b, c = Tenancy.with_tenant(buyer.id) do
      [ [ beta, { cancelled_at: Time.current } ], [ alpha, { accepted_at: Time.current } ], [ beta, {} ] ].map do |tenant, attributes|
        FactoryBot.create(:purchase_order, supplier_tenant_id: tenant.id, **attributes)
      end
    end

    expect(list_ids(order_by: [ { field: :supplier_name, direction: :asc } ])).to eq([ [ b, a, c ].map(&:id), 3 ])
    expect(list_ids(order_by: [ { field: :status, direction: :asc } ])).to eq([ [ c, b, a ].map(&:id), 3 ])
    expect(list_ids(order_by: [ { field: :status, direction: :desc } ])).to eq([ [ a, b, c ].map(&:id), 3 ])
  end
end

# 発注の進みのタイムライン。状況の式が読む行に取消依頼と受領請求書を足した自社の行だけから組み立て、時刻の出来事は日本時間の日付と時刻で、日付の出来事は
# 同じ日の時刻の出来事の後ろに業務の順で並べる（docs/architecture/graphql-schema.md「発注側の視点」）
RSpec.describe Purchasing::PurchaseOrders, ".timeline_for" do
  include ActiveSupport::Testing::TimeHelpers

  let!(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: buyer.id, name: "", email: "", role: "member", partner_code: "") }

  def at(text) = Time.zone.parse(text)

  def timeline(ids) = Tenancy.with_tenant(buyer.id) { described_class.timeline_for(actor, ids) }

  def entries(values) = values.map { [ _1.kind, _1.occurred_on, _1.occurred_at ] }

  # 受注確定・取消依頼・却下・再依頼・承認と、出荷・検収・請求書の受領を経た発注。検収と請求書の受領は同じ日で、
  # 請求書を先に作るので、行の ID の順は業務の順と逆になる
  def walked_order
    FactoryBot.create(:purchase_order, created_at: at("2026-10-01 10:00"), awaiting_match_at: at("2026-10-01 11:00"),
      accepted_at: at("2026-10-02 09:30"), cancelled_at: at("2026-10-03 15:00")).tap do |order|
      FactoryBot.create(:cancellation_request, purchase_order: order, created_at: at("2026-10-02 10:00"), outcome: "rejected",
        decided_at: at("2026-10-02 12:00"))
      FactoryBot.create(:cancellation_request, purchase_order: order, created_at: at("2026-10-03 10:00"), outcome: "approved",
        decided_at: at("2026-10-03 15:00"))
      line = FactoryBot.create(:purchase_order_line, purchase_order: order)
      shipment = FactoryBot.create(:inbound_shipment, purchase_order: order, shipped_on: Date.new(2026, 10, 3))
      FactoryBot.create(:received_invoice_line, purchase_order_line: line,
        received_invoice: FactoryBot.create(:received_invoice, issued_on: Date.new(2026, 10, 5)))
      FactoryBot.create(:receipt_inspection, inbound_shipment: shipment, inspected_on: Date.new(2026, 10, 5))
    end
  end

  it "出来事を、日付、時刻（空は後ろ）、業務の順で並べ、取消の承認で書く発注の取消の時刻を別の出来事にしない" do
    order = Tenancy.with_tenant(buyer.id) { walked_order }

    expect(entries(timeline([ order.id ]).fetch(order.id))).to eq([
      [ :ordered, Date.new(2026, 10, 1), at("2026-10-01 10:00") ],
      [ :part_match_pending, Date.new(2026, 10, 1), at("2026-10-01 11:00") ],
      [ :accepted, Date.new(2026, 10, 2), at("2026-10-02 09:30") ],
      [ :cancellation_requested, Date.new(2026, 10, 2), at("2026-10-02 10:00") ],
      [ :cancellation_rejected, Date.new(2026, 10, 2), at("2026-10-02 12:00") ],
      [ :cancellation_requested, Date.new(2026, 10, 3), at("2026-10-03 10:00") ],
      [ :cancellation_approved, Date.new(2026, 10, 3), at("2026-10-03 15:00") ],
      [ :shipped, Date.new(2026, 10, 3), nil ],
      [ :inspected, Date.new(2026, 10, 5), nil ],
      [ :invoice_received, Date.new(2026, 10, 5), nil ]
    ])
    expect(timeline([ order.id ]).fetch(order.id).map(&:owner_tenant_id)).to all(eq(buyer.id))
  end

  # 却下と受注側の取消が同じ時刻のとき、行の ID の順（発注が先）は業務の順（却下が先）と逆になる
  it "受注側の取消を出来事にし、同じ時刻の出来事は行の ID の順ではなく業務の順で並べる" do
    order = Tenancy.with_tenant(buyer.id) do
      FactoryBot.create(:purchase_order, created_at: at("2026-10-01 10:00"), supplier_cancelled_at: at("2026-10-01 12:00")).tap do
        FactoryBot.create(:cancellation_request, purchase_order: _1, created_at: at("2026-10-01 11:00"), outcome: "rejected",
          decided_at: at("2026-10-01 12:00"))
      end
    end

    expect(timeline([ order.id ]).fetch(order.id).map(&:kind))
      .to eq(%i[ordered cancellation_requested cancellation_rejected supplier_cancelled])
  end

  # 回答待ちの依頼は回答の時刻を持たないので、回答の出来事を出さない
  it "回答待ちの取消依頼は、取消依頼だけを出す" do
    order = Tenancy.with_tenant(buyer.id) do
      FactoryBot.create(:purchase_order, created_at: at("2026-10-01 10:00")).tap do
        FactoryBot.create(:cancellation_request, purchase_order: _1, created_at: at("2026-10-01 11:00"))
      end
    end

    expect(entries(timeline([ order.id ]).fetch(order.id))).to eq([
      [ :ordered, Date.new(2026, 10, 1), at("2026-10-01 10:00") ],
      [ :cancellation_requested, Date.new(2026, 10, 1), at("2026-10-01 11:00") ]
    ])
  end

  # 業務の日付は日本時間で決める（docs/guides/testing.md「層への配分」）
  it "日本時間の 0〜9 時に起きた出来事の日付は、日本時間の日付になる" do
    now = Time.utc(2026, 10, 11, 16, 0)
    order = travel_to(now) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:purchase_order) } }

    # 対照：この時刻の UTC の日付は前日である
    expect(now.to_date).to eq(Date.new(2026, 10, 11))
    expect(entries(timeline([ order.id ]).fetch(order.id))).to eq([ [ :ordered, Date.new(2026, 10, 12), now ] ])
  end

  # Bullet は関連の読み込みしか見ないので、発注ごとに問い合わせを繰り返す形を捕まえない。SQL の件数で確かめる
  it "発注が 2 件でも、SQL を 1 回だけ流して両方の出来事を返す" do
    orders = Tenancy.with_tenant(buyer.id) { [ walked_order, FactoryBot.create(:purchase_order, accepted_at: Time.current) ] }
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:cached] || %w[SCHEMA TRANSACTION Tenancy].include?(payload[:name]) }

    values = Tenancy.with_tenant(buyer.id) do
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { described_class.timeline_for(actor, orders.map(&:id)) }
    end

    expect(values.transform_values(&:size)).to eq(orders[0].id => 10, orders[1].id => 2)
    expect(count).to eq(1)
  end

  it "1 通の受領請求書が 2 つの発注の明細を含むと、発注ごとに 1 つずつ請求書の受領を出す" do
    first, second = Tenancy.with_tenant(buyer.id) do
      orders = FactoryBot.create_list(:purchase_order, 2)
      invoice = FactoryBot.create(:received_invoice)
      [ orders[0], orders[0], orders[1] ].each do |order|
        FactoryBot.create(:received_invoice_line, received_invoice: invoice, purchase_order_line: FactoryBot.create(:purchase_order_line, purchase_order: order))
      end
      orders
    end

    values = timeline([ first.id, second.id ])

    expect(values.transform_values { |entries| entries.map(&:kind) })
      .to eq(first.id => %i[ordered invoice_received], second.id => %i[ordered invoice_received])
  end

  # 公開 API は所有の条件を RLS に任せない。RLS の SELECT を開いて他社の行を見えるようにし、どの読み方も自社の発注に結ぶことを確かめる
  # （docs/guides/testing.md「行列テストとの分担」）
  describe "RLS の SELECT と UPDATE を開いたとき" do
    include_context "RLS の SELECT と UPDATE を開く"

    it "他社の発注の ID は空の配列になり、他社の取消依頼・入荷・検収・受領請求書の出来事が混ざらない" do
      other = FactoryBot.create(:tenant)
      theirs = Tenancy.with_tenant(other.id) { walked_order }
      ours = Tenancy.with_tenant(buyer.id) { FactoryBot.create(:purchase_order, created_at: at("2026-10-01 10:00")) }

      values = Tenancy.with_tenant(buyer.id) do
        cross_read!
        # 対照：開いた後は、他社の発注が見える
        expect(Purchasing::PurchaseOrder.where(id: theirs.id)).to exist
        described_class.timeline_for(actor, [ ours.id, theirs.id ])
      end

      # 対照：自社の発注の出来事は返る
      expect(entries(values.fetch(ours.id))).to eq([ [ :ordered, Date.new(2026, 10, 1), at("2026-10-01 10:00") ] ])
      expect(values.fetch(theirs.id)).to eq([])
    end
  end
end
