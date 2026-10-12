require_relative "tenant_helpers"
require_relative "matrix_cross_read"

# 行列テストの世界（docs/architecture/context-map.md「テナントと所有」、docs/architecture/data-model.md「RLS」）。ペルソナごとにテナントと、
# admin と member のユーザーを 1 人ずつ作り、
# テナントの表ごとに、どのペルソナも自社の行を factory で 1 件以上持つようにする。
# そのうえで、supplier が受注側になる取引関係を 3 つ結び、supplier の公開品目を 1 件足す
# （表ごとの行は factory の既定のままなので、品目は公開しない）。
# さらに supplier と取引関係を結んだ発注側ごとに、supplier への発注と、それに連結した supplier の受注と出荷実績を 1 組足す。
# 連結元の ID を持ち合う行でも、相手からは見えないことと、出荷実績を読む経路 3 が付与と失効に従うことを確かめるためである。
# 最後に、どのペルソナにもダッシュボードの各集計に当たる行と、一覧の絞り込みに当たる行を足す
class MatrixWorld
  include TenantHelpers

  PERSONAS = %i[supplier granted_buyer ungranted_buyer revoked_buyer stranger].freeze

  ALL_PERMISSIONS = %w[view_catalog place_orders view_shipments].freeze

  # 一覧の絞り込みに当たる行の受注日・発注日と品目名。factory の既定の日付（今日）と品目名の行は当たらない
  FILTER_ORDER_DATE = Date.new(2000, 1, 1)
  FILTER_ITEM_NAME = "絞り込みの品目".freeze

  # supplier との取引関係。revoked_buyer は全権限の付与を持ったまま失効させ、付与があっても失効で閉じることを確かめる
  PARTNERSHIPS = {
    granted_buyer: { permissions: ALL_PERMISSIONS },
    ungranted_buyer: { permissions: [] },
    revoked_buyer: { permissions: ALL_PERMISSIONS, traits: [ :revoked ] }
  }.freeze

  # users は admin、members は member のユーザー
  attr_reader :tenants, :users, :members

  # 行列の spec のファイルごとに、世界を 1 回だけ作って全 example で使い回す（docs/guides/testing.md「行列テストとの分担」）。
  # example ごとに作ると、表の数に比例する世界を表の数に比例する example ぶん作り、時間が表の数の 2 乗で伸びる。
  # 各 example は、rspec-rails が世界と同じ接続の上に開くセーブポイントの中で動き、終わりに巻き戻る。
  # cross_read: true は、世界を開く前に RLS の SELECT と UPDATE を開くポリシーを足し、世界を閉じた後に外す（MatrixCrossRead.share）。
  # 世界のトランザクションが表のロックを持つ間は足し外しが待ち合うので、ポリシーのフックを世界のフックより先に登録して順を固定する。
  # rspec は before(:context) が失敗しても after(:context) を走らせるので、世界を開く途中の失敗でもポリシーは外れる
  def self.share_per_file(group, cross_read: false)
    MatrixCrossRead.share(group) if cross_read
    group.before(:context) { @matrix_world = MatrixWorld.open }
    group.after(:context) { MatrixWorld.close if @matrix_world }
    group.let(:world) { @matrix_world }
  end

  # 接続を固定し、外側のトランザクションの中に世界を作る。作る途中で失敗したら、固定を外してから送出する。
  # before(:context) は rspec-rails の example ごとのトランザクションの外で動くので、固定しないと世界がコミットされる。
  # pin_connection! は Rails の公開の文書に無いメソッドで、transactional fixtures も同じものを使う。
  # lock_thread は transactional fixtures の既定（lock_threads）と同じ真にし、example の固定と同じ形にそろえる
  def self.open
    pool = ActiveRecord::Base.connection_pool
    world = nil
    begin
      pool.pin_connection!(true)
      world = new.freeze.tap { check_tenant_cleared! }
    ensure
      unpin_after_failure(pool) unless world
    end
  end

  # pin_connection! は接続を固定して入れ子の数を足してから、接続の確かめと BEGIN を行うので、そこで失敗しても足した分を外す。
  # 接続を借りる前に失敗したときは固定が無く、unpin_connection! が固定の無いことを例外にするので、それだけは捨てる
  def self.unpin_after_failure(pool)
    pool.unpin_connection!
  rescue RuntimeError => e
    raise unless e.message.start_with?("There isn't a pinned connection")
  end
  private_class_method :unpin_after_failure

  # 世界のトランザクションを巻き戻し、接続の固定を外す。unpin_connection! が偽を返すのは、世界のトランザクションが
  # ファイルの終わりより前にコミットされたか巻き戻ったときで、その後の example は世界の無い DB で動いたことになる
  def self.close
    return if ActiveRecord::Base.connection_pool.unpin_connection!

    raise "行列の世界のトランザクションが、ファイルの終わりより前に閉じた。example が世界の接続でコミットしたか巻き戻した"
  end

  # 世界を作った後に、テナントの設定が残っていないことを確かめる。残っていると、外側のトランザクションの終わりまで
  # 全 example に渡り、example の生 SQL が残ったテナントで RLS を通って、行列の結果が変わる。
  # example の中で設定した値は、example のセーブポイントと一緒に巻き戻る
  def self.check_tenant_cleared!
    setting = ActiveRecord::Base.lease_connection.select_value("SELECT current_setting('app.tenant_id', true)")
    return if setting.blank? && Current.tenant_id.nil?

    raise "テナントの設定が残っている（app.tenant_id: #{setting.inspect}、Current.tenant_id: #{Current.tenant_id.inspect}）"
  end

  def self.tenant_tables
    ActiveRecord::Base.lease_connection.select_values(<<~SQL)
      SELECT table_name FROM information_schema.columns
      WHERE table_schema = 'public' AND column_name = 'owner_tenant_id'
      ORDER BY table_name
    SQL
  end

  # 表の行を作る factory。名前は表の単数形にする
  def self.factory_name(table) = table.singularize.to_sym

  def initialize
    @tenants = PERSONAS.index_with { |persona| create_tenant(persona.to_s) }
    @users = PERSONAS.index_with { |persona| as(persona) { FactoryBot.create(:user, :admin) } }
    @members = PERSONAS.index_with { |persona| as(persona) { FactoryBot.create(:user) } }
    @rows = self.class.tenant_tables.index_with do |table|
      PERSONAS.index_with { |persona| as(persona) { FactoryBot.create(self.class.factory_name(table)) } }
    end
    @partnerships = PARTNERSHIPS.to_h do |buyer, spec|
      partnership = as(:supplier) do
        FactoryBot.create(:partnership, *spec.fetch(:traits, []), buyer_tenant_id: tenants[buyer], permissions: spec[:permissions])
      end
      [ buyer, partnership ]
    end
    as(:supplier) { FactoryBot.create(:item, :published) }
    @linked_orders = PARTNERSHIPS.keys.index_with { |buyer| link_orders(buyer) }
    PERSONAS.each do |persona|
      as(persona) do
        add_dashboard_rows(persona)
        add_filter_rows
      end
    end
  end

  # 世界のオブジェクトを example の間で使い回すので、属性を凍らせ、example の中の属性の代入を例外にする。
  # reload・destroy と、関連先のインスタンスの書き換えは捕まえない。行列の spec はそれらを呼ばない規則で守る
  # 行の書き換えは DB の上で巻き戻るが、オブジェクトの書き換えは巻き戻らず、後の example に渡る
  def freeze
    [ @tenants, @users, @members, @partnerships, *@rows.values, *@linked_orders.values ].each do |records|
      records.each_value(&:freeze).freeze
    end
    [ @rows, @linked_orders ].each(&:freeze)
    super
  end

  # supplier と buyer の取引関係
  def partnership(buyer) = @partnerships.fetch(buyer)

  # buyer の発注と、それに連結した supplier の受注と出荷実績（:purchase_order・:sales_order・:shipment）
  def linked_order(side, buyer = :granted_buyer) = @linked_orders.fetch(buyer).fetch(side)

  def as(persona, &)
    Tenancy.with_tenant(tenants.fetch(persona), &)
  end

  # ペルソナがその表に所有する行の 1 つ
  def row(table, persona) = @rows.fetch(table).fetch(persona)

  def persona_of(tenant_id) = tenants.key(tenant_id) || tenant_id

  private

  # ダッシュボードの集計に当たる行。受注と未請求の明細は表ごとの行で足りる。在庫と出荷依頼は、factory の既定では
  # 安全在庫を割らず期限も無いので、ここで足す。どの集計も自社の行を数えるので、集計の公開 API が scope を外すと、
  # RLS の SELECT を開いた入口の行列で他社のこの行が数に入る（docs/guides/testing.md「行列テストとの分担」）。
  # 在庫はダッシュボードが品目のコードで並べるので、自社の品目に作る
  def add_dashboard_rows(persona)
    FactoryBot.create(:stock, item_id: row("items", persona).id, on_hand: 1, safety_stock: 2)
    FactoryBot.create(:shipment_request, due_date: Date.current)
  end

  # 一覧の絞り込み（入口の行列の "#filter" の行）に当たる行。どのペルソナにも当たる行と当たらない行があるので、
  # 公開 API が絞り込みか件数の scope を外すと、RLS の SELECT を開いた入口の行列で他社のこの行が応答に入る。
  # 受注と発注は、列の絞り込みに当たる取消済の行が当たり、取消していない行は状況で外れる。
  # 在庫の安全在庫はダッシュボードの行が当たる。出荷依頼は、表ごとの行とダッシュボードの行（出荷待ち）が当たり、取消済の行が外れる
  def add_filter_rows
    [ nil, Time.current ].each do |cancelled_at|
      FactoryBot.create(:sales_order, customer_tenant_id: tenants[:granted_buyer], order_date: FILTER_ORDER_DATE, cancelled_at:)
      FactoryBot.create(:purchase_order, supplier_tenant_id: tenants[:supplier], order_date: FILTER_ORDER_DATE, cancelled_at:)
    end
    FactoryBot.create(:shipment_request, due_date: Date.current, cancelled_at: Time.current)
    FactoryBot.create(:stock_movement, type: "outbound")
    FactoryBot.create(:item, name: FILTER_ITEM_NAME)
  end

  # 受注側の ACL が「発注登録」から作るのと同じ形に、発注と受注を明細ごと連結し、
  # 出荷が「出荷可能」から作るのと同じ形に、受注を全量で出荷する
  def link_orders(buyer)
    purchase_order = as(buyer) { FactoryBot.create(:purchase_order, supplier_tenant_id: tenants[:supplier]) }
    purchase_order_line = as(buyer) { FactoryBot.create(:purchase_order_line, purchase_order:) }
    as(:supplier) do
      sales_order = FactoryBot.create(:sales_order, customer_tenant_id: tenants[buyer], source_purchase_order_id: purchase_order.id)
      sales_order_line = FactoryBot.create(:sales_order_line, :matched, sales_order:,
        source_purchase_order_line_id: purchase_order_line.id, customer_part_number: purchase_order_line.part_number)
      request = FactoryBot.create(:shipment_request, sales_order_id: sales_order.id, buyer_tenant_id: tenants[buyer],
        source_purchase_order_id: purchase_order.id)
      request_line = FactoryBot.create(:shipment_request_line, shipment_request: request, sales_order_line_id: sales_order_line.id,
        source_purchase_order_line_id: purchase_order_line.id, item_id: sales_order_line.item_id)
      shipment = FactoryBot.create(:shipment, shipping_instruction: FactoryBot.create(:shipping_instruction, shipment_request: request))
      FactoryBot.create(:shipment_line, shipment:, shipment_request_line: request_line)
      { purchase_order:, sales_order:, shipment: }
    end
  end
end
