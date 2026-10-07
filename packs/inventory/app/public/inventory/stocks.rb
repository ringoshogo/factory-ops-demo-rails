module Inventory
  # 受注側が自社の在庫と移動履歴を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）
  module Stocks
    def self.list(actor, first:, after:)
      Page.of(Scope.call(actor, Stock.all), first:, after:) { |stocks| stocks.map { to_value(_1) } }
    end

    # 品目 ID ごとの在庫。在庫の行が無い品目は含まない
    def self.for_items(actor, item_ids)
      Scope.call(actor, Stock.all).where(item_id: item_ids).to_h { [ _1.item_id, to_value(_1) ] }
    end

    def self.movements(actor, item_id: nil, first:, after:)
      relation = Scope.call(actor, StockMovement.all)
      relation = relation.where(item_id:) if item_id
      Page.of(relation, first:, after:) do |movements|
        movements.map { StockMovementValue.new(**_1.slice(*StockMovementValue.members.map(&:to_s)).symbolize_keys) }
      end
    end

    def self.to_value(stock)
      StockValue.new(owner_tenant_id: stock.owner_tenant_id, item_id: stock.item_id, on_hand: stock.on_hand,
        allocated: stock.allocated, available: stock.available, safety_stock: stock.safety_stock,
        below_safety_stock: stock.available < stock.safety_stock)
    end
  end
end
