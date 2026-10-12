require "rails_helper"
require "prism"

# パッケージのコードで行ロックかアドバイザリロックを取るメソッドと、ロックを取る DB の関数（トリガーなど）は、
# そのロックで直列になることを確かめる競合テストか、競合テストを持たない理由を、下の表に持つ（docs/guides/testing.md「競合テスト」）。
# ロックを足しても、直列になることを確かめなければ、ロックを外しても何も落ちない
RSpec.describe "ロックを取るメソッドと競合テスト" do
  # ロックを取るメソッド（「定数.メソッド」）と DB の関数（「DB:関数名」）ごとに、確かめる競合テスト（spec:）と、
  # その spec に現れるべき文字列（mentions:）を書く。mentions を省くと、メソッドは定数の最後の名前と「.メソッド」の 2 つを、
  # DB の関数は関数名を見る。競合テストを持たないなら、理由（reason:）を書く
  SITES = {
    "Billing::Closing.close" => { spec: "packs/billing/spec/concurrency/billing/closing_lock_spec.rb" },
    "Billing::Closing.discard" => { spec: "packs/billing/spec/concurrency/billing/closing_lock_spec.rb" },
    "Billing::Closing.issue" => { spec: "packs/billing/spec/concurrency/billing/closing_lock_spec.rb" },
    "DB:invoice_children_issued_immutable" => {
      spec: "packs/billing/spec/concurrency/billing/closing_lock_spec.rb", mentions: [ "公開 API を通らない明細の書き換え", "確定した請求書は変えられない" ]
    },
    "Fulfillment::Instructions.create" => {
      reason: "出荷依頼の行ロックで、出荷停止の受け手・計上と直列になる。同じロックの待ちは、計上と出荷停止の受け手の競合テストが確かめる"
    },
    "Fulfillment::Instructions.cancel" => { spec: "packs/fulfillment/spec/concurrency/fulfillment/shipping_lock_spec.rb" },
    "Fulfillment::SalesEventReceiver.hold" => {
      spec: "packs/fulfillment/spec/concurrency/fulfillment/shipping_lock_spec.rb", mentions: %w[SalesEventReceiver ShippingHeld]
    },
    "Fulfillment::SalesEventReceiver.lock_sales_order" => {
      spec: "packs/fulfillment/spec/concurrency/fulfillment/shipping_hold_lock_spec.rb",
      mentions: %w[SalesEventReceiver ShippingHeld SalesOrderReadyForShipment]
    },
    "Fulfillment::SalesEventReceiver.cancel" => {
      reason: "出荷取消の受け手。取消と計上のどちらか一方だけが成立することは、受注側の在庫の行と引当の行のロックが決め、" \
        "spec/concurrency/cancel_vs_ship_spec.rb が確かめる。出荷依頼の行ロックは、その後に届く取消を計上の後に並べるだけである"
    },
    "Fulfillment::Shipping.post" => { spec: "packs/fulfillment/spec/concurrency/fulfillment/shipping_lock_spec.rb" },
    "Inventory::Stock.lock_for" => { spec: "packs/inventory/spec/concurrency/inventory/stock_lock_spec.rb" },
    "Imports::Chunk.locked" => {
      spec: "packs/imports/spec/concurrency/imports/parallel_imports_spec.rb", mentions: %w[Staging.run Applying.next_chunk Finalizing.run]
    },
    "Imports::Files.purge_abandoned" => { spec: "packs/imports/spec/concurrency/imports/purge_lock_spec.rb" },
    "Imports::Runs.start" => { spec: "packs/imports/spec/concurrency/imports/purge_lock_spec.rb" },
    "Inventory::Adjustment.adjust" => { spec: "spec/concurrency/stock_allocation_spec.rb" },
    "Inventory::Adjustment.set_quantity" => {
      spec: "packs/imports/spec/concurrency/imports/parallel_imports_spec.rb", mentions: %w[Adjustment.set_quantity Applying.next_chunk]
    },
    "Inventory::Allocation.allocate" => { spec: "spec/concurrency/stock_allocation_spec.rb" },
    "Inventory::Allocation.move" => { spec: "spec/concurrency/cancel_vs_ship_spec.rb", mentions: %w[OrderCancellation.cancel Shipping.post] },
    "Inventory::Allocation.locked_allocations" => {
      spec: "spec/concurrency/cancel_vs_ship_spec.rb", mentions: %w[OrderCancellation.cancel Shipping.post]
    },
    "Notifications::CriticalDeliveryJob.perform" => { spec: "packs/notifications/spec/concurrency/notifications/delivery_lock_spec.rb" },
    "Notifications::Email.redeliver_failed" => {
      reason: "運用者が rake タスクから流す再送の操作。同時の再送は送信記録の行ロックで直列になり、待った側は失敗の時刻を消した行を" \
        "条件で外すので、同じ送信記録のジョブを 2 つ登録しない。2 つ登録しても、送信のジョブが受け付けを見て 2 通目を送らない"
    },
    "Notifications::ProcessInboxJob.apply" => { spec: "packs/notifications/spec/concurrency/notifications/delivery_lock_spec.rb" },
    "Notifications::ProcessInboxJob.process_batch" => { spec: "packs/notifications/spec/concurrency/notifications/delivery_lock_spec.rb" },
    "Partnerships::Access.lock_pair!" => { spec: "packs/purchasing/spec/concurrency/purchasing/ordering_lock_spec.rb", mentions: %w[Ordering.place] },
    "Partnerships::Access.permitted?" => { spec: "packs/purchasing/spec/concurrency/purchasing/ordering_lock_spec.rb", mentions: %w[Ordering.place] },
    "Partnerships::Management.with_active_partnership" => {
      spec: "packs/purchasing/spec/concurrency/purchasing/ordering_lock_spec.rb", mentions: %w[Management.revoke Management.withdraw]
    },
    "Purchasing::Ordering.place" => { spec: "packs/purchasing/spec/concurrency/purchasing/ordering_lock_spec.rb" },
    "Purchasing::Ordering.request_cancellation" => {
      reason: "発注の行ロックで同じ発注への依頼を直列にし、回答待ちの依頼が発注ごとに 1 件であることは部分一意索引が最後に守る"
    },
    "Purchasing::ReceiptInspections.record" => { spec: "packs/purchasing/spec/concurrency/purchasing/receipt_inspections_lock_spec.rb" },
    "Purchasing::SupplierEventReceiver.handle" => {
      reason: "受注側からのイベントの受け手。どの書き込みも時刻か回答が空のときだけ書くので、同じ発注への配送が並んでも結果は変わらない"
    },
    "Purchasing::SupplierEventReceiver.answer_cancellation" => {
      reason: "回答が空のときだけ書く。同じ取消依頼への回答は審査の決着が 1 回だけ出す（cancellation_reviews_lock_spec.rb）"
    },
    "Sales::OrderCancelling.cancel" => {
      spec: "spec/concurrency/cancel_vs_ship_spec.rb", mentions: %w[OrderCancellation.cancel CancellationReviews.approve]
    },
    "Sales::PartMatching.lock" => { spec: "packs/sales/spec/concurrency/sales/part_mappings_spec.rb" },
    "Sales::CancellationReviews.decide" => {
      spec: "packs/sales/spec/concurrency/sales/cancellation_reviews_lock_spec.rb", mentions: %w[.approve .reject]
    },
    "Sales::ItemPrices.schedule" => { spec: "packs/sales/spec/concurrency/sales/item_prices_lock_spec.rb" },
    "Sales::ItemPrices.correct" => { spec: "packs/sales/spec/concurrency/sales/item_prices_lock_spec.rb" },
    "Sales::Catalog.save" => { reason: "自社の品目だけを書き、相手のイベントと競わない。同じコードの重複は一意索引が守る" },
    "Sales::Catalog.set_published" => { reason: "自社の品目の公開の状態だけを書き、最後の書き込みが残ってよい" },
    "Sales::FulfillmentEventReceiver.ship" => {
      reason: "「出荷計上」の受け手。受注の時刻が空のときだけ書くので、同じ受注への配送が並んでも結果は変わらない"
    },
    "Sales::OrderAllocation.allocate" => { spec: "packs/sales/spec/concurrency/sales/order_allocation_lock_spec.rb" },
    "Sales::OrderCancellation.cancel" => { spec: "packs/sales/spec/concurrency/sales/order_cancellation_lock_spec.rb" },
    "Sales::PartMappings.register" => { spec: "packs/sales/spec/concurrency/sales/part_mappings_spec.rb" },
    "Sales::PartMappings.rematch" => { spec: "packs/sales/spec/concurrency/sales/part_mappings_spec.rb", mentions: %w[PartMappings .register] },
    "Sales::PurchaseOrderTranslator.handle" => { spec: "packs/sales/spec/concurrency/sales/part_mappings_spec.rb" },
    "Sales::PurchasingEventReceiver.review" => {
      spec: "packs/sales/spec/concurrency/sales/order_cancellation_lock_spec.rb", mentions: %w[PurchasingEventReceiver.handle CancellationRequested]
    },
    "Sales::PurchasingEventReceiver.inspect_shipment" => {
      reason: "「検収完了」の受け手。検収の記録は出荷実績 ID ごとに 1 回だけ書き、同じ入荷の 2 回目の検収は購買の行ロックが止める" \
        "（receipt_inspections_lock_spec.rb）"
    }
  }.freeze

  # ファイルの構文木から、ロックを取る呼び出しを含むメソッドを「定数.メソッド」で集める
  # SQL の文の中の行ロックとアドバイザリロック。FOR SHARE も、待たせる相手がいるので数える
  SQL_LOCK = /\bFOR\s+(?:NO\s+KEY\s+UPDATE|UPDATE|KEY\s+SHARE|SHARE)\b|pg_advisory_xact_lock/i

  class LockSiteCollector < Prism::Visitor
    LOCK_CALLS = %i[lock lock! lock_for lock_pair! with_lock].freeze

    attr_reader :sites

    def initialize
      super
      @namespace = []
      @method = nil
      @sites = []
    end

    def visit_module_node(node) = within(node) { super }
    def visit_class_node(node) = within(node) { super }

    def visit_def_node(node)
      outer, @method = @method, node.name
      super
    ensure
      @method = outer
    end

    # 受け手の無い lock は、ほかの名前（引数やローカル変数）とぶつかりうるので、受け手のある呼び出しだけを数える
    def visit_call_node(node)
      record if LOCK_CALLS.include?(node.name) && (node.receiver || %i[lock_for lock_pair! lock!].include?(node.name))
      super
    end

    # permitted?(..., lock: true) のように、ロックを取らせる引数を渡す呼び出し
    def visit_assoc_node(node)
      record if node.key.is_a?(Prism::SymbolNode) && node.key.unescaped == "lock" && node.value.is_a?(Prism::TrueNode)
      super
    end

    def visit_string_node(node)
      record if node.unescaped.match?(SQL_LOCK)
      super
    end

    private

    def within(node)
      @namespace.push(node.constant_path.full_name)
      yield
    ensure
      @namespace.pop
    end

    def record = @sites << "#{@namespace.join('::')}.#{@method}"
  end

  def self.collect(source)
    LockSiteCollector.new.tap { Prism.parse(source).value.accept(_1) }.sites.uniq
  end

  # structure.sql の関数のうち、本体でロックを取るものを「DB:関数名」で集める。トリガーは公開 API を通らない書き込みにも効くので、
  # パッケージのコードの表と同じく、直列になることを確かめる競合テストを求める
  def self.collect_db(structure_sql)
    structure_sql.scan(/^CREATE FUNCTION public\.(\w+)\(.*?AS \$\$(.*?)\$\$;/m)
      .select { |_name, body| body.match?(SQL_LOCK) }.map { |name, _body| "DB:#{name}" }
  end

  def self.lock_sites
    ruby = Dir[Rails.root.join("packs/*/app/**/*.rb")].sort.flat_map { collect(File.read(_1)) }
    (ruby + collect_db(Rails.root.join("db/structure.sql").read)).uniq.sort
  end

  def self.default_mentions(name)
    return [ name.delete_prefix("DB:") ] if name.start_with?("DB:")

    constant, method = name.split(".", 2)
    [ constant.split("::").last, ".#{method}" ]
  end

  def self.missing_mentions(name, entry)
    path = Rails.root.join(entry.fetch(:spec))
    return [ "#{entry.fetch(:spec)} が無い" ] unless path.exist?
    return [ "#{entry.fetch(:spec)} は concurrency の置き場に無い" ] unless entry.fetch(:spec).include?("/concurrency/")

    mentions = entry.fetch(:mentions) { default_mentions(name) }
    text = path.read
    mentions.reject { text.include?(_1) }
  end

  it "ロックを取るメソッドと DB の関数は、すべて表にあり、表のものはすべてロックを取る" do
    expect(self.class.lock_sites).to eq(SITES.keys.sort)
  end

  SITES.each do |name, entry|
    if entry.key?(:spec)
      it "#{name} のロックを、#{File.basename(entry.fetch(:spec))} が確かめる" do
        expect(self.class.missing_mentions(name, entry)).to eq([])
      end
    else
      it "#{name} が競合テストを持たない理由がある" do
        expect(entry.fetch(:reason)).to be_present
      end
    end
  end

  describe "集め方" do
    it "行ロック・ロックを取らせる引数・アドバイザリロックを、囲むメソッドの名前で拾う" do
      source = <<~RUBY
        module Shop
          module Orders
            def self.take(id) = Order.lock.find(id)
            def self.place(actor) = Access.permitted?(actor, lock: true)
            def self.serialize = connection.select_value("SELECT pg_advisory_xact_lock(1)")
            def self.read(id) = Order.find(id)
            def self.keyword(lock: false) = lock
          end
        end
      RUBY

      expect(self.class.collect(source)).to eq(%w[Shop::Orders.take Shop::Orders.place Shop::Orders.serialize])
    end

    it "本体でロックを取る DB の関数を、関数名で拾う" do
      sql = <<~SQL
        CREATE FUNCTION public.guard_child() RETURNS trigger
            LANGUAGE plpgsql
            AS $$
        BEGIN
          SELECT issued_at INTO issued FROM public.invoices WHERE id = NEW.invoice_id FOR SHARE;
          RETURN NEW;
        END
        $$;

        CREATE FUNCTION public.plain() RETURNS trigger
            LANGUAGE plpgsql
            AS $$ BEGIN RETURN NEW; END $$;

        CREATE FUNCTION public.serialize() RETURNS void
            LANGUAGE sql
            AS $$ SELECT pg_advisory_xact_lock(1) $$;
      SQL

      expect(self.class.collect_db(sql)).to eq(%w[DB:guard_child DB:serialize])
    end

    it "表に無いメソッドと、spec に現れない呼び出しを落とす" do
      expect(self.class.missing_mentions("Billing::Closing.reopen", spec: "packs/billing/spec/concurrency/billing/closing_lock_spec.rb"))
        .to eq([ ".reopen" ])
      expect(self.class.missing_mentions("Billing::Closing.close", spec: "packs/billing/spec/public/billing/closing_spec.rb"))
        .to eq([ "packs/billing/spec/public/billing/closing_spec.rb は concurrency の置き場に無い" ])
    end
  end
end
