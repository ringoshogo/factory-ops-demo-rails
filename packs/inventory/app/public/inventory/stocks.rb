module Inventory
  # 受注側が自社の在庫と移動履歴を読み、安全在庫を変える（docs/architecture/graphql-schema.md「読み取りの一覧」）
  module Stocks
    class ProductionEnvironment < StandardError; end

    # 安全在庫の上限。列の型（integer）の最大値で、超えた値は保存の時点で ActiveModel::RangeError になる
    MAX_SAFETY_STOCK = 2_147_483_647

    LABELS = ItemLabel.arel_table

    # 並べてよい列（docs/architecture/graphql-schema.md「ページングと N+1」）。有効在庫は現在庫 - 引当の式で、
    # 品目のコードと名前は品目の写しの列で並べる
    ORDER_COLUMNS = {
      on_hand: [ Stock.arel_table[:on_hand], :integer ],
      allocated: [ Stock.arel_table[:allocated], :integer ],
      available: [ Stock.arel_table[:on_hand] - Stock.arel_table[:allocated], :integer ],
      safety_stock: [ Stock.arel_table[:safety_stock], :integer ],
      item_code: [ LABELS[:code], :string ],
      item_name: [ LABELS[:name], :string ]
    }.freeze

    # order_by は { field:, direction: } の配列で、1 つ目の列から順に並べる。空なら作った順の新しいものから並べる。
    # filter の below_safety_stock が真なら、ダッシュボードの安全在庫（below_safety_stock）と同じ条件で絞る。
    # filter の keyword は、品目の一覧の keyword と同じ規則で、品目の写しのコードか名前を検索する（Keyword）。
    # 写しの無い在庫は、品目のコードと名前で並べると最後に置かれ、keyword には当たらない
    def self.list(actor, first:, after:, order_by: [], filter: {})
      relation = filtered(labeled(Scope.call(actor, Stock.all)), **filter)
      Page.of(relation, first:, after:, sort: Page::Sort.of(order_by, ORDER_COLUMNS)) do |stocks|
        stocks.map { to_value(_1) }
      end
    end

    # 品目 ID ごとの在庫。在庫の行が無い品目は含まない
    def self.for_items(actor, item_ids)
      Scope.call(actor, Stock.all).where(item_id: item_ids).to_h { [ _1.item_id, to_value(_1) ] }
    end

    # 品目 ID ごとの安全在庫を返す副問い合わせ。受注の品目の一覧が、安全在庫で並べるために結ぶ（docs/architecture/graphql-schema.md「ページングと N+1」）。
    # 操作者の scope を掛けた後に SQL の文字列にするので、受け取る側は所有の条件を外せない。在庫は所有テナントと品目 ID の組で一意なので、
    # 品目ごとに高々 1 行になる。役割の名前（item_id・safety_stock）を返し、受け取る側が在庫の列を書かない
    def self.safety_stocks_sql(actor)
      SqlSubquery.of(Scope.call(actor, Stock.all).select(:item_id, :safety_stock), item_id: "item_id", safety_stock: "safety_stock")
    end

    # 有効在庫が安全在庫より小さい在庫。等しい在庫は返さない（docs/architecture/data-model.md「在庫（`inventory`）」）。
    # 在庫は品目コードを持たないので、並べ替えと件数の上限はルートパッケージが品目コードで行う
    def self.below_safety_stock(actor)
      Scope.call(actor, Stock.below_safety_stock).order(:item_id).map { to_value(_1) }
    end

    # filter の types は移動の種類で絞る。空の配列は 0 件で、nil なら絞らない
    def self.movements(actor, item_id: nil, first:, after:, filter: {})
      relation = Scope.call(actor, StockMovement.all)
      relation = relation.where(item_id:) if item_id
      Page.of(movements_filtered(relation, **filter), first:, after:) do |movements|
        movements.map { StockMovementValue.new(**_1.slice(*StockMovementValue.members.map(&:to_s)).symbolize_keys) }
      end
    end

    # 自社の在庫の行の安全在庫を変える。シードと E2E の世界の準備のためのもので、GraphQL の入口は無く、本番の環境では
    # DEMO_WORLD_ENABLED=1 を渡したプロセスでだけ呼べる（Platform::DemoWorldGate）。
    # 役割は問わない（在庫の調整と同じ）。在庫の行の無い品目と他社の品目は NOT_FOUND にする
    def self.set_safety_stock(actor, item_id:, safety_stock:)
      raise ProductionEnvironment, "Inventory::Stocks.set_safety_stock は本番の環境では DEMO_WORLD_ENABLED=1 のときだけ呼べる" unless Platform::DemoWorldGate.open?
      unless safety_stock.is_a?(Integer) && safety_stock.between?(0, MAX_SAFETY_STOCK)
        return OperationResult.failure(:invalid_input, path: [ :safety_stock ],
          message: "Safety stock must be an integer between 0 and #{MAX_SAFETY_STOCK}")
      end

      Stock.transaction(requires_new: true) do
        stock = Scope.call(actor, Stock.where(item_id:)).lock.first
        next OperationResult.failure(:not_found, path: [ :item_id ]) unless stock

        stock.change_safety_stock!(safety_stock)
        OperationResult.success(to_value(stock))
      end
    end

    # 在庫の行に、同じ所有テナントの同じ品目の写しを外部結合する。所有テナントの組で結ぶのは、在庫の scope が絞った所有テナントを
    # 写しにも掛けるためで、品目 ID だけで結ぶと、他社の名義で同じ品目 ID を指す写しを RLS が見せたときに、それを並びと検索に使う
    def self.labeled(relation)
      stocks = Stock.arel_table
      relation.joins(stocks.join(LABELS, Arel::Nodes::OuterJoin)
        .on(LABELS[:owner_tenant_id].eq(stocks[:owner_tenant_id]).and(LABELS[:item_id].eq(stocks[:item_id]))).join_sources)
    end

    def self.filtered(relation, below_safety_stock: nil, keyword: nil)
      relation = relation.below_safety_stock if below_safety_stock
      Keyword.search(relation, keyword, LABELS[:code], LABELS[:name])
    end

    def self.movements_filtered(relation, types: nil)
      types.nil? ? relation : relation.where(type: types)
    end
    private_class_method :labeled, :filtered, :movements_filtered

    def self.to_value(stock)
      StockValue.new(owner_tenant_id: stock.owner_tenant_id, item_id: stock.item_id, on_hand: stock.on_hand,
        allocated: stock.allocated, available: stock.available, safety_stock: stock.safety_stock,
        below_safety_stock: stock.available < stock.safety_stock)
    end
  end
end
