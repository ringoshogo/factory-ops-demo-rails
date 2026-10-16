module Inventory
  # 入庫・出庫による在庫の調整（docs/architecture/graphql-schema.md「mutation の一覧」adjustStock）。
  # 在庫は自社の品目にだけできる。品目は、受注の公開 API が品目と同じトランザクションで書く自社の写し（ItemLabel）で確かめ、
  # 写しの無い品目 ID は何も書かずに NOT_FOUND にする（docs/architecture/data-model.md「在庫（`inventory`）」）
  module Adjustment
    TYPES = %w[inbound outbound].freeze
    # 調整の理由の長さの上限（docs/architecture/graphql-schema.md「mutation の一覧」）
    MAX_REASON_LENGTH = 200

    # 出庫は有効在庫までに限る。引き当てた分を出庫すると、出荷で消費する在庫が無くなるからである
    def self.adjust(actor, item_id:, type:, quantity:, reason: nil)
      return invalid_input(:type, "Type must be one of #{TYPES.join(', ')}") unless TYPES.include?(type)
      return invalid_input(:quantity, "Quantity must be positive") unless quantity.is_a?(Integer) && quantity.positive?
      if reason && reason.length > MAX_REASON_LENGTH
        return invalid_input(:reason, "Reason must be at most #{MAX_REASON_LENGTH} characters")
      end

      return not_found unless labeled?(actor, item_id)

      result = nil
      Stock.transaction(requires_new: true) do
        stock = Stock.lock_for(actor.tenant_id, [ item_id ]).fetch(item_id)
        if type == "outbound" && quantity > stock.available
          result = invalid_input(:quantity, "Quantity must be at most the available stock (#{stock.available})")
          raise ActiveRecord::Rollback
        end

        stock.move!(type, quantity, reason:)
        result = OperationResult.success(Stocks.to_value(stock))
      end
      result
    end

    # 在庫数を目標の数量に合わせる（CSV の在庫の取り込み）。在庫の行をロックしてから差を取り、差を入庫か出庫で移す。
    # ロックの前に読んだ数量で差を取ると、同時の調整や引当とずれる。引当済みの数量より少ない目標は受け付けない
    def self.set_quantity(actor, item_id:, quantity:, reason:)
      return invalid_input(:quantity, "Quantity must be a non-negative integer") unless quantity.is_a?(Integer) && quantity >= 0
      return not_found unless labeled?(actor, item_id)

      result = nil
      Stock.transaction(requires_new: true) do
        stock = Stock.lock_for(actor.tenant_id, [ item_id ]).fetch(item_id)
        if quantity < stock.allocated
          result = invalid_input(:quantity, "Quantity must be at least the allocated stock (#{stock.allocated})")
          raise ActiveRecord::Rollback
        end

        difference = quantity - stock.on_hand
        stock.move!(difference.positive? ? "inbound" : "outbound", difference.abs, reason:) unless difference.zero?
        result = OperationResult.success(Stocks.to_value(stock))
      end
      result
    end

    # 写しは消さないので、確かめてから在庫の行をロックするまでの間に消えることは無い。写しの行はロックしない
    def self.labeled?(actor, item_id) = Scope.call(actor, ItemLabel.where(item_id:)).exists?

    def self.invalid_input(attribute, message) = OperationResult.failure(:invalid_input, path: [ attribute ], message:)
    # 取り込みが行の失敗の文に写すので、文を持たせる
    def self.not_found = OperationResult.failure(:not_found, path: [ :item_id ], message: "Item must be one of the own items")
    private_class_method :labeled?, :invalid_input, :not_found
  end
end
