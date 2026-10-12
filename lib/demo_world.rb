require "csv"

# デモの世界を、公開 API とイベントだけで作る。受注側の青嵐精機工業と、発注側の架空の組立メーカー 2 社（全権限の付与ありと、
# 失効済み）と、各社の admin と member、品目・在庫・取引・請求・取り込みを作る。シード（db/seeds.rb）と E2E の世界が
# この 1 つの作り方を使い、片方だけが古くならないようにする（README.md「開発環境」）。
# 業務の表へ直接書かないので、RLS と policy を通る。公開 API は、テナントごとに Tenancy.with_tenant を開き、そのテナントの admin を
# 操作者にして呼ぶ。admin に限る操作は Operations を通して、mutation と同じ規則を評価してから呼ぶ。
# 各段の後に、登録されたイベントと取り込みのジョブを Jobs でその場で流す。
# 業務の日付（発注日・受注日・検収日・請求書の発行日）は公開 API が今日で決めるので、シードを流した日の日付になる。
# 入力で渡す日付（希望納期・出荷日・指示の予定日・単価の改定日・締め日）だけを、今日からの差で書く
class DemoWorld
  class ProductionEnvironment < StandardError; end
  class Failed < StandardError; end

  VARIANTS = %i[seed e2e].freeze

  # namespace はテナントのコードとメールアドレスに入るので、英小文字・数字・ハイフンに限る
  NAMESPACE = /\A[a-z0-9-]*\z/

  # アカウント（メールアドレスと共通のパスワード）の一覧はここにだけ置く。デモの手元で使う値で、本番の資格情報ではない
  ACCOUNTS_PATH = Rails.root.join("db/seeds/demo_accounts.json")

  Account = Data.define(:persona, :tenant, :role, :name, :email, :password)
  # tenant_ids は :supplier・:granted_buyer・:revoked_buyer ごとのテナントの ID
  Result = Data.define(:tenant_ids, :accounts)

  # 発注側の 2 社の名前は、流用元（factory-ops-demo の 958de71 の backend/internal/seed/default.go）の得意先 CUS-001・CUS-002 である。
  # 本デモの得意先はテナントで住所と担当者を持たないので、名前だけを写す
  TENANTS = {
    supplier: { code: "seiran", name: "青嵐精機工業" },
    granted_buyer: { code: "tokai-sanki", name: "東海産機システム株式会社", part_prefix: "TS" },
    revoked_buyer: { code: "kitakanto-automation", name: "北関東オートメーション株式会社", part_prefix: "KA" }
  }.freeze
  BUYERS = %i[granted_buyer revoked_buyer].freeze
  PERMISSIONS = %w[view_catalog place_orders view_shipments].freeze

  # 品目のコード・名前・単位・単価・安全在庫・初期在庫。流用元の default.go の ITM-001〜ITM-020 を写す。
  # ITM-006・016 は初期在庫が安全在庫を下回り、ITM-019・020 は流用元と同じく取引にも在庫にも使わない
  ITEMS = [
    [ "ITM-001", "精密ベアリング BR-6205", "個", 1200, 20, 60 ],
    [ "ITM-002", "直動ガイドレール LG-300", "本", 8500, 10, 25 ],
    [ "ITM-003", "タイミングベルト TB-450", "本", 3200, 15, 40 ],
    [ "ITM-004", "ボールねじ BS-1610", "本", 15_800, 5, 12 ],
    [ "ITM-005", "六角穴付きボルト M8x30 (100本入)", "箱", 950, 30, 80 ],
    [ "ITM-006", "オイルシール OS-3552", "個", 480, 40, 30 ],
    [ "ITM-007", "カップリング CP-25", "個", 6400, 8, 18 ],
    [ "ITM-008", "リニアブッシュ LB-12", "個", 2100, 25, 55 ],
    [ "ITM-009", "平歯車 SG-40T", "個", 4700, 12, 20 ],
    [ "ITM-010", "ステンレス平座金 M10 (200枚入)", "箱", 620, 20, 45 ],
    [ "ITM-011", "空圧シリンダ AC-32x100", "個", 11_200, 6, 14 ],
    [ "ITM-012", "ソレノイドバルブ SV-24V", "個", 7800, 10, 22 ],
    [ "ITM-013", "近接センサ PS-M12", "個", 3900, 15, 35 ],
    [ "ITM-014", "アルミフレーム AF-4040 (1m)", "本", 2800, 20, 60 ],
    [ "ITM-015", "減速機 GR-1-20", "台", 42_000, 3, 5 ],
    [ "ITM-016", "Oリング OR-S18 (50個入)", "袋", 350, 25, 12 ],
    [ "ITM-017", "チェーンスプロケット CS-16T", "個", 5300, 10, 26 ],
    [ "ITM-018", "ダンパー DM-60", "個", 9100, 4, 9 ],
    [ "ITM-019", "樹脂プーリ RP-80", "個", 1750, 0, 0 ],
    [ "ITM-020", "防振ゴムマウント VM-25", "個", 2450, 0, 0 ]
  ].freeze
  # カタログに公開しない品目。発注側のカタログに、公開した品目だけが出ることを見せる
  UNPUBLISHED = %w[ITM-019 ITM-020].freeze
  # 期中の追加入庫。流用元と同じく、在庫の移動履歴に入庫の実績を持たせる
  REPLENISHMENTS = { "ITM-001" => 20, "ITM-014" => 10 }.freeze
  TAX_RATE_PERCENT = 10
  # 締め日は月末にする。シードを流す日がどの日でも、その月の末日の締めで、その日に検収した明細が集まる
  CLOSING_DAY = 31

  # 発注。lines は [品目の番号, 数量] で、発注側の得意先品番は「接頭辞-品目の番号」になる。対応表の無い番号の明細は品番照合待ちになる。
  # due_in は希望納期の今日からの差、stage は受注・出荷・検収・請求をどこまで進めるか（advance）
  Order = Data.define(:buyer, :lines, :due_in, :stage)
  UNMAPPED_NUMBER = "900"
  # 受注・発注・出荷依頼の、止まっていられる状況をすべて持つ。発注の「送信済み」は、受注側がイベントを受け取るまでの途中の状況で、
  # その場で流すので残らない
  ORDERS = [
    Order.new(buyer: :granted_buyer, lines: [ [ "001", 10 ], [ "003", 5 ] ], due_in: 7, stage: :issued),
    Order.new(buyer: :granted_buyer, lines: [ [ "010", 6 ] ], due_in: 5, stage: :drafted),
    Order.new(buyer: :granted_buyer, lines: [ [ "013", 4 ] ], due_in: 4, stage: :inspected),
    Order.new(buyer: :granted_buyer, lines: [ [ "008", 12 ] ], due_in: 3, stage: :shipped),
    Order.new(buyer: :granted_buyer, lines: [ [ "012", 5 ], [ "017", 4 ] ], due_in: 2, stage: :instructed),
    Order.new(buyer: :granted_buyer, lines: [ [ "004", 2 ], [ "007", 3 ] ], due_in: 5, stage: :allocated),
    Order.new(buyer: :granted_buyer, lines: [ [ "006", 50 ] ], due_in: 8, stage: :partially_allocated),
    Order.new(buyer: :granted_buyer, lines: [ [ "014", 20 ] ], due_in: 6, stage: :received),
    Order.new(buyer: :granted_buyer, lines: [ [ UNMAPPED_NUMBER, 3 ] ], due_in: 10, stage: :received),
    Order.new(buyer: :granted_buyer, lines: [ [ "011", 2 ] ], due_in: 4, stage: :cancellation_requested),
    Order.new(buyer: :granted_buyer, lines: [ [ "015", 1 ] ], due_in: 9, stage: :cancelled),
    Order.new(buyer: :granted_buyer, lines: [ [ "018", 3 ] ], due_in: 12, stage: :supplier_cancelled),
    Order.new(buyer: :revoked_buyer, lines: [ [ "002", 8 ], [ "005", 4 ] ], due_in: 7, stage: :issued),
    Order.new(buyer: :revoked_buyer, lines: [ [ "014", 10 ] ], due_in: 3, stage: :shipped)
  ].freeze

  # 単価の改定の予約と訂正を 1 件ずつ
  PRICE_SCHEDULE = { code: "ITM-002", unit_price: 8800, effective_in: 30 }.freeze
  PRICE_CORRECTION = { code: "ITM-005", unit_price: 980, reason: "仕入先の価格表の転記の誤り" }.freeze

  # 一部の行が失敗する品目の取り込み。ITM-019 を公開し、ITM-021 を足し、税率の誤った ITM-022 の行を失敗にする
  IMPORT_ROWS = [
    [ "ITM-019", "樹脂プーリ RP-80", "個", 10, true, nil, nil ],
    [ "ITM-021", "ステンレスシャフト SF-12 (1m)", "本", 10, true, 3600, nil ],
    [ "ITM-022", "真鍮スペーサー BS-6", "個", 5, true, 80, nil ]
  ].freeze

  # E2E の世界だけに足す、画面の折り返しとはみ出しを測るための長い名前の品目と取引先と、取り込みの残りの状況
  # （失敗と完了）。長い名前の品目は発注にも使い、受注と発注の明細にも出す
  LONG_ITEM = [ "ITM-030", "超高精度クロスローラーベアリング 薄型シリーズ CRB-12025 両側シール付き・防錆処理済み（クリーンルーム対応品）",
    "個", 12_800, 2, 10 ].freeze
  LONG_BUYER_NAME = "東海産機システム株式会社 第二工場 自動化設備調達センター（試作ライン・量産ライン共通窓口）"
  E2E_ORDERS = [ Order.new(buyer: :granted_buyer, lines: [ [ "030", 2 ], [ "016", 5 ] ], due_in: 14, stage: :received) ].freeze

  def self.build(namespace:, variant:) = new(namespace:, variant:).build

  def initialize(namespace:, variant:)
    raise ArgumentError, "namespace は英小文字・数字・ハイフンにする: #{namespace.inspect}" unless namespace.is_a?(String) && namespace.match?(NAMESPACE)
    raise ArgumentError, "variant は #{VARIANTS.join('・')} のどれかにする: #{variant.inspect}" unless VARIANTS.include?(variant)

    @namespace = namespace
    @variant = variant
  end

  # 同じ namespace の受注側のテナントがあれば、何も作らずに、あるテナントとアカウントを返す
  def build
    raise ProductionEnvironment, "DemoWorld は本番の環境では DEMO_WORLD_ENABLED=1 のときだけ動く" unless Platform::DemoWorldGate.open?

    existing = Partnerships::Onboarding.tenant_id(code: code_of(:supplier))
    return Result.new(tenant_ids: TENANTS.keys.index_with { Partnerships::Onboarding.tenant_id(code: code_of(_1)) }, accounts:) if existing

    register_tenants
    build_catalog
    build_partnerships
    ORDERS.each { place_and_advance(_1) }
    import("items", "items.csv", IMPORT_ROWS)
    build_e2e_extras if @variant == :e2e
    as(:supplier) { |actor| success!(Operations.revoke_partnership(actor, partnership_id: @partnership_ids.fetch(:revoked_buyer))) }
    Result.new(tenant_ids: @tenant_ids, accounts:)
  end

  def accounts
    @accounts ||= begin
      data = JSON.parse(ACCOUNTS_PATH.read)
      data.fetch("accounts").map do |account|
        local, domain = account.fetch("email").split("@", 2)
        email = @namespace.empty? ? account.fetch("email") : "#{local}+#{@namespace}@#{domain}"
        Account.new(persona: account.fetch("persona"), tenant: account.fetch("tenant").to_sym, role: account.fetch("role"),
          name: account.fetch("name"), email:, password: data.fetch("password"))
      end
    end
  end

  private

  def code_of(tenant) = [ TENANTS.fetch(tenant).fetch(:code), @namespace.presence ].compact.join("-")

  def name_of(tenant)
    name = @variant == :e2e && tenant == :granted_buyer ? LONG_BUYER_NAME : TENANTS.fetch(tenant).fetch(:name)
    @namespace.empty? ? name : "#{name}（#{@namespace}）"
  end

  def register_tenants
    @tenant_ids = {}
    @partner_codes = {}
    @actors = {}
    TENANTS.each_key do |tenant|
      @partner_codes[tenant] = SecureRandom.hex(16)
      users = accounts.select { _1.tenant == tenant }.map { { email: _1.email, name: _1.name, role: _1.role, password: _1.password } }
      @tenant_ids[tenant] = Partnerships::Onboarding.register(name: name_of(tenant), code: code_of(tenant),
        partner_code: @partner_codes[tenant], users:)
      @actors[tenant] = login(accounts.find { _1.tenant == tenant && _1.role == "admin" })
    end
  end

  # ログインと同じ入口でユーザーを引き、そのユーザーを操作者にする
  def login(account)
    login = Partnerships::Authentication.authenticate(email: account.email, password: account.password) or
      raise Failed, "#{account.email} でログインできない"
    Tenancy.with_tenant(login.tenant_id) { Partnerships::Authentication.acting_user(login.user_id) }
  end

  # テナントの admin を操作者にしてブロックを実行し、その後に登録されたイベントと取り込みのジョブを流す
  def as(tenant)
    result = Tenancy.with_tenant(@tenant_ids.fetch(tenant)) { yield @actors.fetch(tenant) }
    Jobs.drain
    result
  end

  def success!(result)
    return result.value if result.success?

    raise Failed, result.failures.map { [ _1.code, _1.path&.join("."), _1.message ].compact.join(" ") }.join("、")
  end

  def build_catalog
    @item_ids = {}
    as(:supplier) do |actor|
      ITEMS.each { add_item(actor, *_1) }
      REPLENISHMENTS.each do |code, quantity|
        success!(Inventory::Adjustment.adjust(actor, item_id: @item_ids.fetch(code), type: "inbound", quantity:, reason: "定期補充入庫"))
      end
      item_id = @item_ids.fetch(PRICE_SCHEDULE[:code])
      success!(Operations.schedule_item_price(actor, item_id:, unit_price: PRICE_SCHEDULE[:unit_price],
        effective_on: Date.current + PRICE_SCHEDULE[:effective_in]))
      item_id = @item_ids.fetch(PRICE_CORRECTION[:code])
      current = Sales::ItemPrices.history(actor, [ item_id ]).fetch(item_id).sole
      success!(Operations.correct_item_price(actor, item_price_id: current.id, unit_price: PRICE_CORRECTION[:unit_price],
        reason: PRICE_CORRECTION[:reason]))
    end
  end

  def add_item(actor, code, name, unit, unit_price, safety_stock, initial_stock)
    item = success!(Sales::Catalog.save(actor, code:, name:, unit:, unit_price:, tax_rate_percent: TAX_RATE_PERCENT))
    success!(Sales::Catalog.set_published(actor, item_id: item.id, published: true)) unless UNPUBLISHED.include?(code)
    @item_ids[code] = item.id
    return if initial_stock.zero?

    success!(Inventory::Adjustment.adjust(actor, item_id: item.id, type: "inbound", quantity: initial_stock, reason: "初期在庫"))
    success!(Inventory::Stocks.set_safety_stock(actor, item_id: item.id, safety_stock:))
  end

  # 取引関係を結んで全権限を付与し、請求条件と、発注側の得意先品番の対応表を作る
  def build_partnerships
    @partnership_ids = {}
    as(:supplier) do |actor|
      BUYERS.each do |buyer|
        partnership = success!(Operations.establish_partnership(actor, partner_code: @partner_codes.fetch(buyer)))
        @partnership_ids[buyer] = partnership.id
        PERMISSIONS.each { success!(Operations.grant_permission(actor, partnership_id: partnership.id, permission: _1)) }
        success!(Operations.set_billing_term(actor, customer_tenant_id: @tenant_ids.fetch(buyer), closing_day: CLOSING_DAY))
        ITEMS.each { |code, *| map_part(actor, buyer, code) }
      end
    end
  end

  def map_part(actor, buyer, code)
    success!(Sales::PartMappings.register(actor, customer_tenant_id: @tenant_ids.fetch(buyer),
      customer_part_number: part_number(buyer, code.delete_prefix("ITM-")), item_id: @item_ids.fetch(code)))
  end

  def part_number(buyer, number) = "#{TENANTS.fetch(buyer).fetch(:part_prefix)}-#{number}"

  # 発注を登録し、受注側が作った受注を、stage まで進める
  def place_and_advance(order)
    purchase_order = as(order.buyer) do |actor|
      success!(Purchasing::Ordering.place(actor, supplier_tenant_id: @tenant_ids.fetch(:supplier),
        lines: order.lines.map { |number, quantity| { part_number: part_number(order.buyer, number), quantity: } },
        desired_delivery_on: Date.current + order.due_in))
    end
    # 発注ごとにイベントを流し終えてから次へ進むので、最も新しい受注が、この発注から作った受注である
    sales_order = as(:supplier) { |actor| Sales::SalesOrders.list(actor, first: 1, after: nil).values.sole }
    raise Failed, "発注 #{purchase_order.order_no} の受注が無い" unless sales_order.customer_tenant_id == @tenant_ids.fetch(order.buyer)

    advance(order, purchase_order, sales_order)
  end

  def advance(order, purchase_order, sales_order)
    case order.stage
    when :received then nil
    when :allocated, :partially_allocated then allocate(sales_order)
    when :instructed then ship(sales_order, post: false)
    when :shipped then ship(sales_order)
    when :inspected, :drafted, :issued
      ship(sales_order)
      inspect_receipt(order.buyer, purchase_order)
      bill(order.buyer, issue: order.stage == :issued) unless order.stage == :inspected
    when :cancellation_requested then request_cancellation(order.buyer, sales_order, purchase_order)
    when :cancelled then decide_cancellation(request_cancellation(order.buyer, sales_order, purchase_order))
    when :supplier_cancelled
      as(:supplier) { |actor| success!(Operations.cancel_sales_order(actor, sales_order_id: sales_order.id)) }
    else raise ArgumentError, "unknown stage: #{order.stage}"
    end
  end

  # 有効在庫の範囲で引き当てる。全量を引き当てると「出荷可能」が出て、出荷依頼ができる。足りなければ一部引当になる
  def allocate(sales_order)
    as(:supplier) { |actor| success!(Sales::OrderAllocation.allocate(actor, sales_order_id: sales_order.id)) }
  end

  def ship(sales_order, post: true)
    allocate(sales_order)
    as(:supplier) do |actor|
      request = Fulfillment::ShipmentRequests.for_sales_orders(actor, [ sales_order.id ]).fetch(sales_order.id)
      success!(Fulfillment::Instructions.create(actor, shipment_request_id: request.id, planned_date: Date.current))
      success!(Fulfillment::Shipping.post(actor, shipment_request_id: request.id, shipped_on: Date.current)) if post
    end
  end

  # 入荷の全明細を全量で受け入れる
  def inspect_receipt(buyer, purchase_order)
    as(buyer) do |actor|
      inbound = Purchasing::PurchaseOrders.inbound_shipments_for(actor, [ purchase_order.id ]).fetch(purchase_order.id).sole
      lines = Purchasing::PurchaseOrders.inbound_shipment_lines_for(actor, [ inbound.id ]).fetch(inbound.id)
        .map { { inbound_shipment_line_id: _1.id, accepted_quantity: _1.shipped_quantity } }
      success!(Operations.inspect_inbound_shipment(actor, inbound_shipment_id: inbound.id, lines:))
    end
  end

  # 取引先ごとに、今月の月末から 1 か月ずつ後の締め日で締める。前の請求書の期間の後の締め日でないと締められないからである
  def bill(buyer, issue:)
    @closings ||= Hash.new(0)
    closing_date = (Date.current >> @closings[buyer]).end_of_month
    @closings[buyer] += 1
    as(:supplier) do |actor|
      invoice = success!(Operations.close_billing_period(actor, customer_tenant_id: @tenant_ids.fetch(buyer), closing_date:))
      success!(Operations.issue_invoice(actor, invoice_id: invoice.id)) if issue
    end
  end

  # 引き当てて出荷依頼を作ってから取消を依頼する。受注側に審査ができ、出荷依頼は出荷停止中になる
  def request_cancellation(buyer, sales_order, purchase_order)
    allocate(sales_order)
    as(buyer) do |actor|
      success!(Operations.request_purchase_order_cancellation(actor, purchase_order_id: purchase_order.id, reason: "生産計画の変更"))
    end
    sales_order
  end

  def decide_cancellation(sales_order)
    as(:supplier) do |actor|
      review = Sales::CancellationReviews.for_sales_orders(actor, [ sales_order.id ]).fetch(sales_order.id).sole
      success!(Operations.approve_cancellation_review(actor, cancellation_review_id: review.id))
    end
  end

  # ファイルを置いて取り込みを始め、ジョブを流し終えた後に、取り込みが終わっていることを確かめる
  def import(kind, filename, rows, header: Imports::CsvFormat::COLUMNS.fetch(kind))
    content = CSV.generate { |csv| [ header, *rows ].each { csv << _1 } }
    import = as(:supplier) do |actor|
      file = success!(Imports::Files.store(actor, filename:, content:))
      success!(Operations.start_import(actor, file_id: file.id, kind:))
    end
    status = Tenancy.with_tenant(@tenant_ids.fetch(:supplier)) { Imports::Runs.find(@actors.fetch(:supplier), import.id).status }
    raise Failed, "取り込み #{filename} が終わらない（#{status}）" unless %i[succeeded partially_failed failed].include?(status)
  end

  def build_e2e_extras
    code = LONG_ITEM.first
    as(:supplier) do |actor|
      add_item(actor, *LONG_ITEM)
      map_part(actor, :granted_buyer, code)
    end
    E2E_ORDERS.each { place_and_advance(_1) }
    # 見出しの誤ったファイルは、行を見ずに取り込み全体を失敗にする
    import("stocks", "stocks-broken.csv", [ [ "ITM-001", 5 ] ], header: %w[code quantity])
    import("stocks", "stocks.csv", [ [ "ITM-019", 15 ], [ "ITM-020", 8 ] ])
  end
end
