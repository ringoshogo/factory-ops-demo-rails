require "rails_helper"
require_relative "../../../../../spec/support/owner_connection"
require_relative "../../../../../spec/support/cross_read"

# 既存の品目の単価と受注明細の有効日を、単価の履歴の形へ写すデータの移行（docs/adr/006 決定 1、docs/adr/001 決定 4）。
# 移行の前の DB の形（items.unit_price があり、照合済みの明細の priced_on が空でよい）は、列を消した後のテストの DB には無い。
# そのため所有ロールで列を足し直し、CHECK 制約を外してから行を作り、example の後で行を消して元の形に戻す。
# 所有ロールの変更はコミットしないとアプリのロールの接続から見えないので、例ごとのトランザクションを使わない
RSpec.describe "Sales::ItemPrices.backfill" do
  include ConcurrencyHelpers
  include ActiveSupport::Testing::TimeHelpers
  include_context "RLS の SELECT を開く"

  self.use_transactional_tests = false

  # 受注明細の「揃って空か揃って埋まる」CHECK 制約の、移行の前の定義（priced_on を含まない）
  matched_before = "(item_id IS NULL AND item_name IS NULL AND unit_price IS NULL AND tax_rate_percent IS NULL) OR " \
    "(item_id IS NOT NULL AND item_name IS NOT NULL AND unit_price IS NOT NULL AND tax_rate_percent IS NOT NULL)"
  # 同じ制約の、db/structure.sql と同じいまの定義
  matched_together = "(item_id IS NULL AND item_name IS NULL AND unit_price IS NULL AND priced_on IS NULL AND tax_rate_percent IS NULL) OR " \
    "(item_id IS NOT NULL AND item_name IS NOT NULL AND unit_price IS NOT NULL AND priced_on IS NOT NULL AND tax_rate_percent IS NOT NULL)"

  let(:owner) { OwnerConnection.lease_connection }
  let!(:tenant) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }

  # 所有ロールが表の形を変えた後は、アプリのロールの接続が準備した文を捨てる。列の増減で、準備した文の結果の型が変わるからである
  # 所有ロールの接続がトランザクションの中にあると、表の形の変更がコミットされず、アプリのロールの接続がそのロックを待ち続ける
  def reshape(sql)
    raise "所有ロールの接続がトランザクションの中にある。前の example の後始末が終わっていない" if owner.transaction_open?

    owner.execute(sql)
    ActiveRecord::Base.connection_pool.connections.each(&:clear_cache!)
  end

  before do
    reshape(<<~SQL)
      ALTER TABLE items ADD COLUMN IF NOT EXISTS unit_price bigint;
      ALTER TABLE sales_order_lines DROP CONSTRAINT sales_order_lines_matched_together;
    SQL
  end

  after do
    delete_owned_rows([ tenant.id, other.id ], %w[item_prices sales_order_lines sales_orders items])
    reshape(<<~SQL)
      ALTER TABLE items DROP COLUMN IF EXISTS unit_price;
      ALTER TABLE sales_order_lines DROP CONSTRAINT IF EXISTS sales_order_lines_matched_together;
      ALTER TABLE sales_order_lines ADD CONSTRAINT sales_order_lines_matched_together CHECK (#{matched_together});
    SQL
  end

  # 後始末が表の形を戻したことを、ファイルの終わりに確かめる。戻し忘れると、後の spec が移行の前の形の DB で流れる
  after(:context) do
    owner = OwnerConnection.lease_connection
    restored = !owner.column_exists?(:items, :unit_price) &&
      owner.select_value("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'sales_order_lines_matched_together'")
        .to_s.include?("priced_on IS NOT NULL")
    raise "移行の spec が、items.unit_price を消すか受注明細の CHECK 制約を戻すのを終えていない" unless restored
  end

  # 移行の前の形の品目と、照合済みで priced_on の空の明細を作る。明細は 10/3 の受注に 120 円で照合したもの
  def legacy_rows(tenant_id, unit_price:)
    Tenancy.with_tenant(tenant_id) do
      item = FactoryBot.create(:item, unit_price: nil)
      order = FactoryBot.create(:sales_order, order_date: Date.new(2026, 10, 3))
      line = FactoryBot.create(:sales_order_line, :matched, sales_order: order, item_id: item.id, priced_on: nil)
      unmatched = FactoryBot.create(:sales_order_line, sales_order: order)
      { item:, line:, unmatched: }
    end.tap { |rows| owner.execute("UPDATE items SET unit_price = #{Integer(unit_price)} WHERE id = #{owner.quote(rows[:item].id)}") }
  end

  def backfill(tenant_id) = Tenancy.with_tenant(tenant_id) { Sales::ItemPrices.backfill }

  def price_rows(tenant_id)
    owner.select_rows(<<~SQL)
      SELECT item_id, unit_price, lower_inf(valid_period) AND upper_inf(valid_period), upper_inf(recorded_period), recorded_by_user_id
      FROM item_prices WHERE owner_tenant_id = #{owner.quote(tenant_id)}
    SQL
  end

  def priced_on(line_id) = owner.select_value("SELECT priced_on FROM sales_order_lines WHERE id = #{owner.quote(line_id)}")

  it "品目の単価を有効期間 (,) の現在の行に写し、照合済みの明細の priced_on を受注日で埋める" do
    rows = legacy_rows(tenant.id, unit_price: 150)
    at = Time.zone.local(2026, 10, 12, 9)

    expect(travel_to(at) { backfill(tenant.id) }).to eq(items: 1, lines: 1)
    expect(price_rows(tenant.id)).to eq([ [ rows[:item].id, 150, true, true, nil ] ])
    expect(owner.select_value("SELECT lower(recorded_period) FROM item_prices WHERE item_id = #{owner.quote(rows[:item].id)}")).to eq(at)
    expect(priced_on(rows[:line].id)).to eq(Date.new(2026, 10, 3))
    expect(priced_on(rows[:unmatched].id)).to be_nil
    expect(Tenancy.with_tenant(tenant.id) { Sales::ItemPrices.price_at(actor_of(tenant), [ rows[:item].id ], valid_on: Date.current) })
      .to eq(rows[:item].id => 150)
  end

  it "もう一度流しても、行も値も変えない" do
    rows = legacy_rows(tenant.id, unit_price: 150)
    backfill(tenant.id)
    before = [ price_rows(tenant.id), priced_on(rows[:line].id) ]

    expect(backfill(tenant.id)).to eq(items: 0, lines: 0)
    expect([ price_rows(tenant.id), priced_on(rows[:line].id) ]).to eq(before)
  end

  it "他のテナントの品目と明細に触れない" do
    mine = legacy_rows(tenant.id, unit_price: 150)
    theirs = legacy_rows(other.id, unit_price: 300)

    backfill(tenant.id)

    expect(price_rows(tenant.id).map(&:first)).to eq([ mine[:item].id ])
    expect(price_rows(other.id)).to be_empty
    expect(priced_on(theirs[:line].id)).to be_nil
  end

  # 操作者のいない入口（rake タスク）の公開 API なので、所有の条件を RLS に任せない
  # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
  it "RLS の SELECT を開いても、他社の品目と明細を数えず、触れない" do
    mine = legacy_rows(tenant.id, unit_price: 150)
    theirs = legacy_rows(other.id, unit_price: 300)

    result = Tenancy.with_tenant(tenant.id) do
      cross_read!
      # 対照：開いた後は、他社の品目が SELECT で見える
      expect(Sales::Item.where(id: theirs[:item].id).exists?).to be(true)
      Sales::ItemPrices.backfill
    end

    expect(result).to eq(items: 1, lines: 1)
    expect(price_rows(tenant.id).map(&:first)).to eq([ mine[:item].id ])
    expect([ price_rows(other.id), priced_on(theirs[:line].id) ]).to eq([ [], nil ])
  end

  # 列を消すマイグレーションを、所有ロールのトランザクションの中で流し、ブロックの後に巻き戻す。
  # bin/rails db:rollback では strong_migrations は down を検査しない。exec_migration は向きを伝えないので、ここで合わせる
  def run_removal(*directions)
    require Rails.root.join("db/migrate/20261012200100_remove_unit_price_from_items").to_s
    owner.transaction do
      directions.each do |direction|
        migration = RemoveUnitPriceFromItems.new
        run = -> { migration.exec_migration(owner, direction) }
        ActiveRecord::Migration.suppress_messages { direction == :down ? migration.safety_assured(&run) : run.call }
      end
      yield if block_given?
      raise ActiveRecord::Rollback
    end
  end

  it "列を消すマイグレーションは、移行の前には止まり、移行の後に通り、巻き戻すと今日の単価を列に戻す" do
    rows = legacy_rows(tenant.id, unit_price: 150)
    expect { run_removal(:up) }.to raise_error(/先に bin\/rails sales:backfill_item_prices を流す/)

    backfill(tenant.id)
    # 移行の前の DB にあった制約を戻す。マイグレーションはこれを外して priced_on を含む制約を足す
    reshape("ALTER TABLE sales_order_lines ADD CONSTRAINT sales_order_lines_matched_together CHECK (#{matched_before})")
    run_removal(:up) { expect(owner.column_exists?(:items, :unit_price)).to be(false) }
    run_removal(:up, :down) do
      expect(owner.select_value("SELECT unit_price FROM items WHERE id = #{owner.quote(rows[:item].id)}")).to eq(150)
    end
  end

  def actor_of(tenant)
    Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "member", partner_code: "")
  end
end
