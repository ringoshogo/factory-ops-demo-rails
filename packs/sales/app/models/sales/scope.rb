module Sales
  # 公開 API が品目を引くときに必ず通す、ItemPolicy の relation_scope
  module Scope
    def self.call(actor, name, **options)
      raise ArgumentError, "actor is required" unless actor.is_a?(Partnerships::Actor)

      ItemPolicy.new(user: actor).apply_scope(Item.all, type: :active_record_relation, name:, scope_options: options.presence)
    end
  end
end
