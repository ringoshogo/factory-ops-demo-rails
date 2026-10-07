module Partnerships
  # 公開 API が取引関係を引くときに必ず通す、PartnershipPolicy の relation_scope
  module Scope
    def self.call(actor, name)
      raise ArgumentError, "actor is required" unless actor.is_a?(Actor)

      PartnershipPolicy.new(user: actor).apply_scope(Partnership.all, type: :active_record_relation, name:)
    end
  end
end
