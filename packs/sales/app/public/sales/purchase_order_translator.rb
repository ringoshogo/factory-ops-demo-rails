module Sales
  # 受注側の腐敗防止層（docs/architecture/context-map.md「発注の連結と品番の照合」2〜4）。
  # 「発注登録」を受け、受注側テナントの名義で受注を作る。得意先品番の対応表で明細を照合し、
  # 全明細が照合できれば「受注確定」を、できなければ「品番照合待ち」を出す。取引関係の状態は見ない。
  # イベントの受け手は操作者のいない入口なので、テナントの設定を求め、所有の条件を RLS に任せずに書き、値を返さない
  # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
  module PurchaseOrderTranslator
    def self.handle(event)
      Tenancy.require_tenant!
      # 連結の冪等キー。2 回目の配送では何もしない。同時に届いた配送は一意索引が止める
      return if SalesOrder.exists?(owner_tenant_id: Current.tenant_id, source_purchase_order_id: event.purchase_order_id)

      SalesOrder.transaction(requires_new: true) do
        PartMatching.lock(event.buyer_tenant_id)
        order = create_order(event)
        order.lines.all?(&:matched?) ? PartMatching.confirm(order) : publish_pending(order)
      end
      nil
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def self.create_order(event)
      items = PartMatching.items(event.buyer_tenant_id, event.lines.map { _1.fetch("part_number") })
      prices = PartMatching.prices(items.values.map(&:id))
      order_date = Date.current
      SalesOrder.create!(
        owner_tenant_id: Current.tenant_id,
        order_no: DocumentNumber.next(SalesOrderSequence, prefix: "SO"),
        customer_tenant_id: event.buyer_tenant_id,
        source_purchase_order_id: event.purchase_order_id,
        order_date:,
        due_date: event.desired_delivery_on&.then { Date.iso8601(_1) },
        lines: event.lines.map do |line|
          SalesOrderLine.new(
            owner_tenant_id: Current.tenant_id,
            source_purchase_order_line_id: line.fetch("purchase_order_line_id"),
            customer_part_number: line.fetch("part_number"),
            quantity: line.fetch("quantity"),
            **PartMatching.copy(items[line.fetch("part_number")], order_date, prices)
          )
        end
      )
    end

    def self.publish_pending(order)
      Contracts.publish(Contracts::PartMatchPending.new(
        purchase_order_id: order.source_purchase_order_id,
        buyer_tenant_id: order.customer_tenant_id,
        supplier_tenant_id: order.owner_tenant_id
      ))
    end
    private_class_method :create_order, :publish_pending
  end
end
