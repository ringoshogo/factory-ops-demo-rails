module Imports
  # 公開 API がファイル・取り込み・置き場の行を引くときに必ず通す、ImportPolicy の relation_scope
  module Scope
    def self.call(actor, relation)
      raise ArgumentError, "actor is required" unless actor.is_a?(Partnerships::Actor)

      ImportPolicy.new(user: actor).apply_scope(relation, type: :active_record_relation, name: :own)
    end
  end
end
