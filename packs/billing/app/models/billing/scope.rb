module Billing
  # 公開 API が請求の行を引くときに必ず通す、InvoicePolicy の relation_scope
  module Scope
    def self.call(actor, relation)
      raise ArgumentError, "actor is required" unless actor.is_a?(Partnerships::Actor)

      InvoicePolicy.new(user: actor).apply_scope(relation, type: :active_record_relation, name: :own)
    end
  end
end
