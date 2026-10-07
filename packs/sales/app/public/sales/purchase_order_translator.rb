module Sales
  # 受注側の腐敗防止層（docs/architecture/context-map.md「発注の連結と品番の照合」2〜4）。
  # 「発注登録」を受け、受注側テナントの名義で受注を作る。得意先品番の対応表で明細を照合し、
  # 全明細が照合できれば「受注確定」を、できなければ「品番照合待ち」を出す。取引関係の状態は見ない
  module PurchaseOrderTranslator
    def self.handle(event)
      # 連結の冪等キー。2 回目の配送では何もしない。同時に届いた配送は一意索引が止める
      return if SalesOrder.exists?(source_purchase_order_id: event.purchase_order_id)

      SalesOrder.transaction(requires_new: true) do
        order = create_order(event)
        order.lines.all?(&:matched?) ? confirm(order) : publish_pending(order)
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def self.create_order(event)
      items = matched_items(event.buyer_tenant_id, event.lines.map { _1.fetch("part_number") })
      SalesOrder.create!(
        owner_tenant_id: Current.tenant_id,
        order_no: DocumentNumber.next(SalesOrderSequence, prefix: "SO"),
        customer_tenant_id: event.buyer_tenant_id,
        source_purchase_order_id: event.purchase_order_id,
        order_date: Date.current,
        due_date: event.desired_delivery_on&.then { Date.iso8601(_1) },
        lines: event.lines.map do |line|
          item = items[line.fetch("part_number")]
          SalesOrderLine.new(
            owner_tenant_id: Current.tenant_id,
            source_purchase_order_line_id: line.fetch("purchase_order_line_id"),
            customer_part_number: line.fetch("part_number"),
            quantity: line.fetch("quantity"),
            # 単価・品目名・税率は照合した時点のカタログの値を写す
            item_id: item&.id, item_name: item&.name, unit_price: item&.unit_price, tax_rate_percent: item&.tax_rate_percent
          )
        end
      )
    end

    # 得意先品番 → 自社品目。対応表と品目は自社の行だけを引く
    def self.matched_items(customer_tenant_id, part_numbers)
      mappings = CustomerPartMapping.includes(:item)
        .where(owner_tenant_id: Current.tenant_id, customer_tenant_id:, customer_part_number: part_numbers)
      mappings.to_h { [ _1.customer_part_number, _1.item ] }
    end

    def self.confirm(order)
      order.update!(confirmed_at: Time.current)
      Contracts.publish(Contracts::SalesOrderConfirmed.new(
        purchase_order_id: order.source_purchase_order_id,
        buyer_tenant_id: order.customer_tenant_id,
        supplier_tenant_id: order.owner_tenant_id,
        lines: order.lines.map do |line|
          { "purchase_order_line_id" => line.source_purchase_order_line_id, "item_name" => line.item_name,
            "unit_price" => line.unit_price.to_s }
        end
      ))
    end

    def self.publish_pending(order)
      Contracts.publish(Contracts::PartMatchPending.new(
        purchase_order_id: order.source_purchase_order_id,
        buyer_tenant_id: order.customer_tenant_id,
        supplier_tenant_id: order.owner_tenant_id
      ))
    end
    private_class_method :create_order, :matched_items, :confirm, :publish_pending
  end
end
