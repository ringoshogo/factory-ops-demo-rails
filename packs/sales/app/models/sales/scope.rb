module Sales
  # 公開 API が品目・受注・対応表を引くときに必ず通す、policy の relation_scope
  module Scope
    def self.call(actor, name, **options)
      apply(ItemPolicy, Item.all, actor, name, options)
    end

    def self.sales_orders(actor, name)
      apply(SalesOrderPolicy, SalesOrder.all, actor, name, {})
    end

    def self.part_mappings(actor, name)
      apply(PartMappingPolicy, CustomerPartMapping.all, actor, name, {})
    end

    def self.apply(policy, relation, actor, name, options)
      raise ArgumentError, "actor is required" unless actor.is_a?(Partnerships::Actor)

      policy.new(user: actor).apply_scope(relation, type: :active_record_relation, name:, scope_options: options.presence)
    end
    private_class_method :apply
  end
end
