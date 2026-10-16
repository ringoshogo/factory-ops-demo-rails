require "rails_helper"

# 得意先品番の対応表の登録と、照合待ちの受注の照合し直し（docs/architecture/context-map.md「発注の連結と品番の照合」5）
RSpec.describe Sales::PartMappings do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:customer) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  around { |example| TenantExample.run(example, supplier.id) }

  before { FactoryBot.create(:partnership, buyer_tenant_id: customer.id) }

  let(:item) { FactoryBot.create(:item, name: "六角ボルト M8", unit_price: 120) }

  def pending_orders(count)
    Array.new(count) do
      FactoryBot.create(:sales_order, customer_tenant_id: customer.id).tap do |order|
        FactoryBot.create(:sales_order_line, sales_order: order, customer_part_number: "MY-BOLT")
        FactoryBot.create(:sales_order_line, :matched, sales_order: order)
      end
    end
  end

  # 一覧のテストの規則で、親を 2 件以上作る（docs/architecture/graphql-schema.md「ページングと N+1」）
  it "照合待ちの受注が 2 件あると、登録で両方の明細を照合して確定し、受注ごとに「受注確定」を出す" do
    orders = pending_orders(2)
    confirmed = []
    allow(Contracts).to receive(:publish).and_wrap_original { |original, event| confirmed << event; original.call(event) }

    result = described_class.register(actor, customer_tenant_id: customer.id, customer_part_number: "MY-BOLT", item_id: item.id)

    expect(result).to be_success
    expect(Sales::SalesOrders.by_ids(actor, orders.map(&:id)).values.map(&:status)).to all(eq(:received))
    expect(confirmed.map(&:purchase_order_id)).to match_array(orders.map(&:source_purchase_order_id))
    expect(confirmed.map { _1.lines.map { |line| line["item_name"] } }).to all(include("六角ボルト M8"))
  end

  # 単価は登録の日ではなく受注日に有効な単価を写す（docs/adr/006 決定 5）
  it "照合し直した明細には、受注日ごとに、その日に有効な単価と受注日を写す" do
    before_revision, after_revision = [ Date.current - 3, Date.current ].map do |order_date|
      FactoryBot.create(:sales_order, customer_tenant_id: customer.id, order_date:).tap do |order|
        FactoryBot.create(:sales_order_line, sales_order: order, customer_part_number: "MY-BOLT")
      end
    end
    # 一昨日までは 120 円、昨日からは 150 円の品目にする
    original = Sales::ItemPrice.find_by!(item_id: item.id)
    at = Time.current
    original.close!(at)
    Sales::ItemPrice.add!(item_id: item.id, unit_price: 120, valid_from: nil, valid_to: Date.current - 1, at:)
    Sales::ItemPrice.add!(item_id: item.id, unit_price: 150, valid_from: Date.current - 1, valid_to: nil, at:)

    register

    copied = [ before_revision, after_revision ].map { |order| Sales::SalesOrderLine.find_by!(sales_order_id: order.id) }
    expect(copied.map { [ _1.unit_price, _1.priced_on ] }).to eq([ [ 120, Date.current - 3 ], [ 150, Date.current ] ])
  end

  it "照合し直して確定した受注ごとに、自社の admin への新しい受注の通知を撃ちっぱなしで送る（docs/adr/007 決定 5 の B-1）" do
    orders = pending_orders(2)
    allow(Notifications::Email).to receive(:deliver_best_effort).and_call_original

    described_class.register(actor, customer_tenant_id: customer.id, customer_part_number: "MY-BOLT", item_id: item.id)

    orders.each do |order|
      expect(Notifications::Email).to have_received(:deliver_best_effort).with(:new_sales_order, params: { order_no: order.order_no })
    end
    expect(Notifications::Email).to have_received(:deliver_best_effort).twice
  end

  def register(customer_tenant_id: customer.id, customer_part_number: "MY-BOLT", item_id: item.id)
    described_class.register(actor, customer_tenant_id:, customer_part_number:, item_id:)
  end

  def status_of(order) = Sales::SalesOrders.find(actor, order.id).status

  def item_names_of(order) = Sales::SalesOrders.lines_for(actor, [ order.id ]).fetch(order.id).map(&:item_name)

  def capture_published = [].tap { |events| allow(Contracts).to receive(:publish).and_wrap_original { |original, event| events << event; original.call(event) } }

  def order_with_lines(*part_numbers, customer_tenant_id: customer.id)
    FactoryBot.create(:sales_order, customer_tenant_id:).tap do |order|
      part_numbers.each { FactoryBot.create(:sales_order_line, sales_order: order, customer_part_number: _1) }
    end
  end

  it "照合できない明細が残る受注は確定せず、「受注確定」も出さない。最後の明細が照合できたときに 1 回だけ出す" do
    nut = FactoryBot.create(:item, name: "六角ナット M8", unit_price: 30)
    order = order_with_lines("MY-BOLT", "MY-NUT")
    events = capture_published

    register
    expect([ status_of(order), item_names_of(order) ]).to eq([ :awaiting_part_match, [ "六角ボルト M8", nil ] ])
    expect(events).to be_empty

    register(customer_part_number: "MY-NUT", item_id: nut.id)
    expect(status_of(order)).to eq(:received)
    expect(events.map(&:class)).to eq([ Contracts::SalesOrderConfirmed ])
  end

  it "既にある対応の品目を差し替えても、確定した受注の明細は照合し直さず、「受注確定」を出し直さない" do
    nut = FactoryBot.create(:item, name: "六角ナット M8", unit_price: 30)
    order = order_with_lines("MY-BOLT")
    events = capture_published
    register

    result = register(item_id: nut.id)

    expect(result.value.item_id).to eq(nut.id)
    expect(item_names_of(order)).to eq([ "六角ボルト M8" ])
    expect(events.map(&:class)).to eq([ Contracts::SalesOrderConfirmed ])
  end

  it "別の取引先の同じ品番の受注は、照合し直さない" do
    other_customer = FactoryBot.create(:tenant)
    FactoryBot.create(:partnership, buyer_tenant_id: other_customer.id)
    order = order_with_lines("MY-BOLT")

    expect(register(customer_tenant_id: other_customer.id)).to be_success
    expect(status_of(order)).to eq(:awaiting_part_match)
  end

  it "失効した取引関係の相手にも登録でき、失効の前の受注を照合して確定する" do
    revoked = FactoryBot.create(:tenant)
    FactoryBot.create(:partnership, :revoked, buyer_tenant_id: revoked.id)
    order = order_with_lines("MY-BOLT", customer_tenant_id: revoked.id)

    expect(register(customer_tenant_id: revoked.id)).to be_success
    expect(status_of(order)).to eq(:received)
  end

  # 相手テナントの品目 ID は、S1（spec/scenarios/tenant_boundary_spec.rb）が registerPartMapping の入口で確かめる
  it "無い品目と、取引関係の無い相手は NOT_FOUND、空の品番は INVALID_INPUT で、対応表に何も残さない" do
    failure = ->(result) { result.failures.map { [ _1.code, _1.path ] } }

    expect(failure.(register(item_id: SecureRandom.uuid))).to eq([ [ :not_found, [ :item_id ] ] ])
    [ FactoryBot.create(:tenant).id, SecureRandom.uuid ].each do |customer_tenant_id|
      expect(failure.(register(customer_tenant_id:))).to eq([ [ :not_found, [ :customer_tenant_id ] ] ])
    end
    expect(failure.(register(customer_part_number: ""))).to eq([ [ :invalid_input, [ :customer_part_number ] ] ])
    expect(described_class.list(actor, first: 10, after: nil).values).to be_empty
  end

  # 明細を受注ごとに引くクエリは、関連の読み込みではないので Bullet に見えない。SQL の数で確かめる
  it "照合し直す受注の明細は、受注の数によらず 1 回で引く" do
    pending_orders(3)
    line_queries = []
    counter = ->(*, payload) { line_queries << payload[:sql] if payload[:sql].start_with?('SELECT "sales_order_lines".') }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      described_class.register(actor, customer_tenant_id: customer.id, customer_part_number: "MY-BOLT", item_id: item.id)
    end

    expect(line_queries.size).to eq(1)
  end
end
