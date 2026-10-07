module Inventory
  # 入庫・出庫による在庫の調整（docs/architecture/graphql-schema.md「mutation の一覧」adjustStock）。
  # 品目の存在は呼ぶ側が受注の公開 API で確かめる。在庫は受注に依存しないからである
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

    def self.invalid_input(attribute, message) = OperationResult.failure(:invalid_input, path: [ attribute ], message:)
    private_class_method :invalid_input
  end
end
