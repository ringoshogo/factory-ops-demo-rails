module Sales
  # 得意先品番の対応表（docs/architecture/context-map.md「発注の連結と品番の照合」5）。対応表は受注側だけが読み書きする
  module PartMappings
    def self.list(actor, customer_tenant_id: nil, first:, after:)
      relation = Scope.part_mappings(actor, :own)
      relation = relation.where(customer_tenant_id:) if customer_tenant_id
      Page.of(relation, first:, after:) { |mappings| mappings.map { to_value(_1) } }
    end

    # 取引先の得意先品番に自社の品目を対応させ、その品番で照合待ちの受注を照合し直す。全明細が照合できた受注は確定する。
    # 取引先は、自社が受注側の取引関係（失効したものを含む）の相手に限る。失効の前の発注も受注まで進むからである。
    # 既にある対応は品目を差し替える。照合済みの明細は変えない
    def self.register(actor, customer_tenant_id:, customer_part_number:, item_id:)
      item = Scope.call(actor, :own).find_by(id: item_id)
      return OperationResult.failure(:not_found, path: [ :item_id ]) unless item
      unless Partnerships::Directory.customer?(actor, customer_tenant_id)
        return OperationResult.failure(:not_found, path: [ :customer_tenant_id ])
      end

      mapping = CustomerPartMapping.transaction(requires_new: true) do
        PartMatching.lock(customer_tenant_id)
        Scope.part_mappings(actor, :own).find_or_initialize_by(customer_tenant_id:, customer_part_number:).tap do |record|
          record.update!(item:)
          rematch(actor, record)
        end
      end
      OperationResult.success(to_value(mapping))
    rescue ActiveRecord::RecordInvalid => e
      error = e.record.errors.first
      OperationResult.failure(:invalid_input, path: [ error.attribute ], message: error.full_message)
    end

    # 確定も取消もされていない受注のうち、この品番の照合前の明細を持つものを、受注 → 受注明細の順にロックして照合する
    def self.rematch(actor, mapping)
      unmatched = SalesOrderLine.where(item_id: nil, customer_part_number: mapping.customer_part_number)
      orders = Scope.sales_orders(actor, :own)
        .where(customer_tenant_id: mapping.customer_tenant_id, confirmed_at: nil, cancelled_at: nil)
        .where(id: unmatched.select(:sales_order_id)).order(:id).lock
      orders.each do |order|
        lines = order.lines.lock.to_a
        lines.select { !_1.matched? && _1.customer_part_number == mapping.customer_part_number }
          .each { _1.update!(PartMatching.copy(mapping.item)) }
        PartMatching.confirm(order) if lines.all?(&:matched?)
      end
    end

    def self.to_value(mapping)
      PartMappingValue.new(**mapping.slice(*PartMappingValue.members.map(&:to_s)).symbolize_keys)
    end
    private_class_method :rematch, :to_value
  end
end
