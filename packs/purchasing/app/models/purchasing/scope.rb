module Purchasing
  # 公開 API が発注と受領請求書を引くときに必ず通す、PurchaseOrderPolicy の relation_scope。relation の既定は発注
  module Scope
    def self.call(actor, name, relation = PurchaseOrder.all)
      raise ArgumentError, "actor is required" unless actor.is_a?(Partnerships::Actor)

      PurchaseOrderPolicy.new(user: actor).apply_scope(relation, type: :active_record_relation, name:)
    end
  end
end
