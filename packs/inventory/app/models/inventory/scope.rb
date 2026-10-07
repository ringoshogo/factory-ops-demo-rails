module Inventory
  # 公開 API が在庫・引当・移動履歴を引くときに必ず通す、policy の relation_scope
  module Scope
    def self.call(actor, relation)
      raise ArgumentError, "actor is required" unless actor.is_a?(Partnerships::Actor)

      StockPolicy.new(user: actor).apply_scope(relation, type: :active_record_relation, name: :own)
    end
  end
end
