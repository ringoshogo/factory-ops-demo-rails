module Purchasing
  # 公開 API が発注を引くときに必ず通す、PurchaseOrderPolicy の relation_scope
  module Scope
    def self.call(actor, name)
      raise ArgumentError, "actor is required" unless actor.is_a?(Partnerships::Actor)

      PurchaseOrderPolicy.new(user: actor).apply_scope(PurchaseOrder.all, type: :active_record_relation, name:)
    end
  end
end
