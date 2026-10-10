require "rails_helper"
require_relative "../../../../../spec/support/events"
require_relative "../../../../../spec/support/shared_examples/idempotent_receiver"

# 購買からのイベントの受注側の受け手。「取消依頼」では審査を作って出荷停止を出し、受注が出荷済みか取消済なら審査を作らずに自動で却下する。
# 「検収完了」では検収数量を記録し、受注を検収済にする
# （docs/architecture/context-map.md「取消の流れ」2・4、「検収と請求の流れ」2、docs/architecture/data-model.md「イベントの受け口と冪等キー」）
RSpec.describe Sales::PurchasingEventReceiver do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:buyer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let!(:order) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:sales_order, customer_tenant_id: buyer.id).tap { FactoryBot.create(:sales_order_line, :matched, sales_order: _1) }
    end
  end
  let(:requested_at) { Time.zone.parse("2026-10-11 09:30:00.123456") }
  let(:event) do
    Contracts::CancellationRequested.new(cancellation_request_id: SecureRandom.uuid, purchase_order_id: order.source_purchase_order_id,
      buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id, requested_at: requested_at.iso8601(6))
  end

  let(:published) { [] }

  before { allow(Contracts).to receive(:publish).and_wrap_original { |original, event| published << event; original.call(event) } }

  def handle(event) = Tenancy.with_tenant(supplier.id) { described_class.handle(event) }

  def reviews = Tenancy.with_tenant(supplier.id) { Sales::CancellationReview.order(:id).to_a }

  it_behaves_like "冪等な受け手" do
    # 発注側が、自社の発注について出す
    let(:publish_event) { -> { Tenancy.with_tenant(buyer.id) { Contracts.publish(event) } } }
    let(:written_rows) { -> { reviews.size } }
  end

  it "受注側テナントの名義で審査中の審査を作り、受注を止める「出荷停止」を出す。受注は取消審査中になる" do
    handle(event)

    review = reviews.sole
    expect(review).to have_attributes(owner_tenant_id: supplier.id, sales_order_id: order.id,
      source_cancellation_request_id: event.cancellation_request_id, requested_at:, decision: nil)
    expect(published.sole).to have_attributes(class: Contracts::ShippingHeld, cancellation_review_id: review.id,
      sales_order_id: order.id, supplier_tenant_id: supplier.id)
    expect(Tenancy.with_tenant(supplier.id) { Sales::SalesOrders.find(actor, order.id) })
      .to have_attributes(status: :received, cancellation_review_pending: true)
  end

  { "出荷済" => :shipped_at, "取消済" => :cancelled_at }.each do |name, column|
    it "受注が#{name}なら、審査を作らずに「取消却下」を出す" do
      Tenancy.with_tenant(supplier.id) { order.update!(column => Time.current) }

      handle(event)

      expect(reviews).to be_empty
      expect(published.sole).to have_attributes(class: Contracts::CancellationRejected,
        cancellation_request_id: event.cancellation_request_id, purchase_order_id: event.purchase_order_id,
        buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id)
    end
  end

  it "受注がまだ無い（発注登録より先に届いた）なら、何も書かずに失敗し、再配送に任せる" do
    expect { handle(event.with(purchase_order_id: SecureRandom.uuid)) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(reviews).to be_empty
    expect(published).to be_empty
  end

  it "発注側テナントが一致しない受注は書かない" do
    expect { handle(event.with(buyer_tenant_id: FactoryBot.create(:tenant).id)) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(reviews).to be_empty
  end

  it "配送表に無い種類のイベントは、審査を書かずに ArgumentError で失敗する" do
    unexpected = Contracts::PartMatchPending.new(purchase_order_id: order.source_purchase_order_id, buyer_tenant_id: buyer.id,
      supplier_tenant_id: supplier.id)

    expect { handle(unexpected) }.to raise_error(ArgumentError, "unexpected event: Contracts::PartMatchPending")
    expect(reviews).to be_empty
  end

  describe "検収完了" do
    let(:shipment_id) { SecureRandom.uuid }
    # 出荷済の受注に、照合済みの明細を 2 つ持たせる
    let!(:shipped_order) do
      Tenancy.with_tenant(supplier.id) do
        FactoryBot.create(:sales_order, customer_tenant_id: buyer.id, shipped_at: Time.current).tap do |order|
          FactoryBot.create_list(:sales_order_line, 2, :matched, sales_order: order, quantity: 4)
        end
      end
    end
    let!(:shipped_lines) { Tenancy.with_tenant(supplier.id) { shipped_order.lines.to_a } }
    let!(:inspected) do
      Contracts::ReceiptInspected.new(shipment_id:, purchase_order_id: shipped_order.source_purchase_order_id,
        buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id, inspected_on: "2026-10-21",
        lines: [
          { "purchase_order_line_id" => shipped_lines[0].source_purchase_order_line_id, "accepted_quantity" => 3 },
          { "purchase_order_line_id" => shipped_lines[1].source_purchase_order_line_id, "accepted_quantity" => 0 }
        ])
    end

    def records
      Tenancy.with_tenant(supplier.id) do
        Sales::InspectionRecord.order(:sales_order_line_id).pluck(:owner_tenant_id, :shipment_id, :sales_order_line_id, :quantity,
          :inspected_on)
      end
    end

    def shipped_order_value = Tenancy.with_tenant(supplier.id) { Sales::SalesOrders.find(actor, shipped_order.id) }

    it_behaves_like "冪等な受け手" do
      # 発注側が、自社の発注について出す
      let(:publish_event) { -> { Tenancy.with_tenant(buyer.id) { Contracts.publish(inspected) } } }
      let(:written_rows) { -> { records.size } }
    end

    it "検収の前の出荷済の受注は、同じ得意先の別の受注の検収完了が届いても検収済にならない" do
      other = Tenancy.with_tenant(supplier.id) do
        FactoryBot.create(:sales_order, customer_tenant_id: buyer.id, shipped_at: Time.current).tap do |order|
          FactoryBot.create(:sales_order_line, :matched, sales_order: order)
        end
      end
      other_line = Tenancy.with_tenant(supplier.id) { other.lines.sole }

      handle(inspected.with(shipment_id: SecureRandom.uuid, purchase_order_id: other.source_purchase_order_id,
        lines: [ { "purchase_order_line_id" => other_line.source_purchase_order_line_id, "accepted_quantity" => 1 } ]))

      expect(Tenancy.with_tenant(supplier.id) { Sales::SalesOrders.find(actor, other.id) }.status).to eq(:inspected)
      expect(shipped_order_value.status).to eq(:shipped)
    end

    it "受注明細ごとに検収数量を記録し、受注を検収済にする。数量 0 の明細も記録する" do
      handle(inspected)

      expect(records).to match_array(shipped_lines.map.with_index do |line, index|
        [ supplier.id, shipment_id, line.id, [ 3, 0 ][index], Date.new(2026, 10, 21) ]
      end)
      expect(shipped_order_value.status).to eq(:inspected)
    end

    it "検収数量が正の受注明細ごとに、受注明細の写しの値で「請求対象確定」を出し、再配送では出し直さない" do
      Tenancy.with_tenant(supplier.id) { shipped_lines[1].update!(item_name: "ナット M8", unit_price: 15, tax_rate_percent: 8) }
      lines = inspected.lines.map { _1.merge("accepted_quantity" => 2) }
      handle(inspected.with(lines:))

      expect(published.map(&:to_h)).to match_array(shipped_lines.map do |line|
        { supplier_tenant_id: supplier.id, buyer_tenant_id: buyer.id, shipment_id:, sales_order_line_id: line.id,
          purchase_order_line_id: line.source_purchase_order_line_id, item_name: line.item_name,
          unit_price: line.unit_price.to_s, tax_rate_percent: line.tax_rate_percent, quantity: 2, inspected_on: "2026-10-21" }
      end)
      expect(published.map { _1.to_h[:item_name] }).to contain_exactly("六角ボルト M8", "ナット M8")

      handle(inspected)
      expect(published.size).to eq(2)
    end

    it "数量 0 の明細には「請求対象確定」を出さない" do
      handle(inspected)

      expect(published.map { [ _1.class, _1.sales_order_line_id, _1.quantity ] })
        .to eq([ [ Contracts::BillableItemConfirmed, shipped_lines[0].id, 3 ] ])
    end

    it "受注側が「出荷計上」をまだ受け取っていない（届く順が入れ替わった）なら、何も書かずに失敗し、再配送に任せる" do
      Tenancy.with_tenant(supplier.id) { shipped_order.update!(shipped_at: nil) }

      expect { handle(inspected) }.to raise_error(Sales::PurchasingEventReceiver::NotShippedYet)
      expect(records).to be_empty
      expect(Tenancy.with_tenant(supplier.id) { shipped_order.reload.inspected_at }).to be_nil
    end

    it "受注がまだ無いか、発注側テナントが一致しない受注は、何も書かずに失敗する" do
      [ inspected.with(purchase_order_id: SecureRandom.uuid), inspected.with(buyer_tenant_id: FactoryBot.create(:tenant).id) ].each do |event|
        expect { handle(event) }.to raise_error(ActiveRecord::RecordNotFound)
      end
      expect(records).to be_empty
    end
  end
end
