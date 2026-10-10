require "rails_helper"
require "prism"

# パッケージのコードで行ロックかアドバイザリロックを取るメソッドは、そのロックで直列になることを確かめる競合テストか、
# 競合テストを持たない理由を、下の表に持つ（docs/guides/testing.md「競合テスト」）。ロックを足しても、
# 直列になることを確かめなければ、ロックを外しても何も落ちない
RSpec.describe "ロックを取るメソッドと競合テスト" do
  # ロックを取るメソッド（「定数.メソッド」）ごとに、確かめる競合テスト（spec:）と、その spec に現れるべき文字列（mentions:）を書く。
  # mentions を省くと、定数の最後の名前と「.メソッド」の 2 つを見る。競合テストを持たないなら、理由（reason:）を書く
  SITES = {
    "Billing::Closing.close" => { spec: "packs/billing/spec/concurrency/billing/closing_lock_spec.rb" },
    "Billing::Closing.discard" => { spec: "packs/billing/spec/concurrency/billing/closing_lock_spec.rb" },
    "Fulfillment::Instructions.create" => {
      reason: "出荷依頼の行ロックで、出荷停止の受け手・計上と直列になる。同じロックの待ちは、計上と出荷停止の受け手の競合テストが確かめる"
    },
    "Fulfillment::Instructions.cancel" => { spec: "packs/fulfillment/spec/concurrency/fulfillment/shipping_lock_spec.rb" },
    "Fulfillment::SalesEventReceiver.hold" => {
      spec: "packs/fulfillment/spec/concurrency/fulfillment/shipping_lock_spec.rb", mentions: %w[SalesEventReceiver ShippingHeld]
    },
    "Fulfillment::SalesEventReceiver.cancel" => {
      reason: "出荷取消の受け手。取消と計上のどちらか一方だけが成立することは、受注側の在庫の行と引当の行のロックが決め、" \
        "spec/concurrency/cancel_vs_ship_spec.rb が確かめる。出荷依頼の行ロックは、その後に届く取消を計上の後に並べるだけである"
    },
    "Fulfillment::Shipping.post" => { spec: "packs/fulfillment/spec/concurrency/fulfillment/shipping_lock_spec.rb" },
    "Inventory::Stock.lock_for" => { spec: "packs/inventory/spec/concurrency/inventory/stock_lock_spec.rb" },
    "Inventory::Adjustment.adjust" => { spec: "spec/concurrency/stock_allocation_spec.rb" },
    "Inventory::Allocation.allocate" => { spec: "spec/concurrency/stock_allocation_spec.rb" },
    "Inventory::Allocation.move" => { spec: "spec/concurrency/cancel_vs_ship_spec.rb", mentions: %w[OrderCancellation.cancel Shipping.post] },
    "Inventory::Allocation.locked_allocations" => {
      spec: "spec/concurrency/cancel_vs_ship_spec.rb", mentions: %w[OrderCancellation.cancel Shipping.post]
    },
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
      record if node.unescaped.match?(/pg_advisory_xact_lock|FOR UPDATE/i)
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

  def self.lock_sites
    Dir[Rails.root.join("packs/*/app/**/*.rb")].sort.flat_map { collect(File.read(_1)) }.uniq.sort
  end

  def self.missing_mentions(name, entry)
    path = Rails.root.join(entry.fetch(:spec))
    return [ "#{entry.fetch(:spec)} が無い" ] unless path.exist?
    return [ "#{entry.fetch(:spec)} は concurrency の置き場に無い" ] unless entry.fetch(:spec).include?("/concurrency/")

    constant, method = name.split(".", 2)
    mentions = entry.fetch(:mentions) { [ constant.split("::").last, ".#{method}" ] }
    text = path.read
    mentions.reject { text.include?(_1) }
  end

  it "ロックを取るメソッドは、すべて表にあり、表のメソッドはすべてロックを取る" do
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

    it "表に無いメソッドと、spec に現れない呼び出しを落とす" do
      expect(self.class.missing_mentions("Billing::Closing.reopen", spec: "packs/billing/spec/concurrency/billing/closing_lock_spec.rb"))
        .to eq([ ".reopen" ])
      expect(self.class.missing_mentions("Billing::Closing.close", spec: "packs/billing/spec/public/billing/closing_spec.rb"))
        .to eq([ "packs/billing/spec/public/billing/closing_spec.rb は concurrency の置き場に無い" ])
    end
  end
end
