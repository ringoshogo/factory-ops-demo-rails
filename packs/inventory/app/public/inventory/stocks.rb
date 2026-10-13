module Inventory
  # 受注側が自社の在庫と移動履歴を読み、安全在庫を変える（docs/architecture/graphql-schema.md「読み取りの一覧」）
  module Stocks
    class ProductionEnvironment < StandardError; end

    # 安全在庫の上限。列の型（integer）の最大値で、超えた値は保存の時点で ActiveModel::RangeError になる
    MAX_SAFETY_STOCK = 2_147_483_647

    # 並べてよい列（docs/architecture/graphql-schema.md「ページングと N+1」）。有効在庫は現在庫 - 引当の式で並べる
    ORDER_COLUMNS = {
      on_hand: [ Stock.arel_table[:on_hand], :integer ],
      allocated: [ Stock.arel_table[:allocated], :integer ],
      available: [ Stock.arel_table[:on_hand] - Stock.arel_table[:allocated], :integer ],
      safety_stock: [ Stock.arel_table[:safety_stock], :integer ]
    }.freeze

    # order_by は { field:, direction: } で、省けば作った順の新しいものから並べる。
    # filter の below_safety_stock が真なら、ダッシュボードの安全在庫（below_safety_stock）と同じ条件で絞る
    def self.list(actor, first:, after:, order_by: nil, filter: {})
      Page.of(filtered(Scope.call(actor, Stock.all), **filter), first:, after:, sort: Page::Sort.of(order_by, ORDER_COLUMNS)) do |stocks|
        stocks.map { to_value(_1) }
      end
    end

    # 品目 ID ごとの在庫。在庫の行が無い品目は含まない
    def self.for_items(actor, item_ids)
      Scope.call(actor, Stock.all).where(item_id: item_ids).to_h { [ _1.item_id, to_value(_1) ] }
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

    def self.filtered(relation, below_safety_stock: nil)
      below_safety_stock ? relation.below_safety_stock : relation
    end

    def self.movements_filtered(relation, types: nil)
      types.nil? ? relation : relation.where(type: types)
    end
    private_class_method :filtered, :movements_filtered

    def self.to_value(stock)
      StockValue.new(owner_tenant_id: stock.owner_tenant_id, item_id: stock.item_id, on_hand: stock.on_hand,
        allocated: stock.allocated, available: stock.available, safety_stock: stock.safety_stock,
        below_safety_stock: stock.available < stock.safety_stock)
    end
  end
end
