module Fulfillment
  # 受注からのイベントの受け手。受注側テナントの名義で、自社の出荷依頼だけを書く
  # （docs/architecture/data-model.md「イベントの受け口と冪等キー」）。取引関係の状態は見ない
  module SalesEventReceiver
    def self.handle(event)
      case event
      when Contracts::SalesOrderReadyForShipment then create_request(event)
      else raise ArgumentError, "unexpected event: #{event.class}"
      end
    end

    # 「出荷可能」の写しを作る。冪等キーは sales_order_id で、2 回目の配送では何もしない。同時に届いた配送は一意索引が止める
    def self.create_request(event)
      return if ShipmentRequest.exists?(sales_order_id: event.sales_order_id)

      ShipmentRequest.transaction(requires_new: true) do
        ShipmentRequest.create!(
          owner_tenant_id: Current.tenant_id,
          sales_order_id: event.sales_order_id,
          buyer_tenant_id: event.buyer_tenant_id,
          source_purchase_order_id: event.purchase_order_id,
          due_date: event.due_date&.then { Date.iso8601(_1) },
          lines: event.lines.map do |line|
            ShipmentRequestLine.new(owner_tenant_id: Current.tenant_id, sales_order_line_id: line.fetch("sales_order_line_id"),
              source_purchase_order_line_id: line.fetch("purchase_order_line_id"), item_id: line.fetch("item_id"),
              quantity: line.fetch("quantity"))
          end
        )
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end
    private_class_method :create_request
  end
end
