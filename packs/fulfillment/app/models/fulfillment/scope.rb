module Fulfillment
  # 公開 API が出荷依頼・出荷指示・出荷実績を引くときに必ず通す、policy の relation_scope
  module Scope
    def self.call(actor, relation, name: :own)
      raise ArgumentError, "actor is required" unless actor.is_a?(Partnerships::Actor)

      ShipmentRequestPolicy.new(user: actor).apply_scope(relation, type: :active_record_relation, name:)
    end
  end
end
