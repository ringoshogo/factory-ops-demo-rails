module Purchasing
  # 受注側からのイベントの受け手。発注側テナントの名義で、自社の発注の時刻列と、明細と入荷の写しだけを書く
  # （docs/architecture/data-model.md「イベントの受け口と冪等キー」）。取引関係の状態は見ない
  module SupplierEventReceiver
    def self.handle(event)
      order = PurchaseOrder.lock.find_by!(owner_tenant_id: Current.tenant_id, id: event.purchase_order_id,
        supplier_tenant_id: event.supplier_tenant_id)

      case event
      when Contracts::SalesOrderConfirmed then accept(order, event)
      when Contracts::PartMatchPending then order.update!(awaiting_match_at: Time.current) unless order.awaiting_match_at
      when Contracts::ShipmentPosted then receive_shipment(order, event)
      else raise ArgumentError, "unexpected event: #{event.class}"
      end
    end

    # 確定した品目名と単価を明細に写す。accepted_at が空のときだけ書く
    def self.accept(order, event)
      return if order.accepted_at

      confirmed = event.lines.index_by { _1.fetch("purchase_order_line_id") }
      order.lines.each do |line|
        values = confirmed.fetch(line.id)
        line.update!(confirmed_item_name: values.fetch("item_name"), confirmed_unit_price: Integer(values.fetch("unit_price")))
      end
      order.update!(accepted_at: Time.current)
    end
    # 「出荷計上」を入荷として写す。冪等キーは shipment_id で、発注の行ロックが同じ出荷の配送を直列にする。
    # 受注 ID と受注明細 ID は保存しない
    def self.receive_shipment(order, event)
      return if InboundShipment.exists?(shipment_id: event.shipment_id)

      lines = order.lines.index_by(&:id)
      order.inbound_shipments.create!(owner_tenant_id: order.owner_tenant_id, shipment_id: event.shipment_id,
        shipped_on: Date.iso8601(event.shipped_on),
        lines: event.lines.map do |line|
          InboundShipmentLine.new(owner_tenant_id: order.owner_tenant_id,
            purchase_order_line: lines.fetch(line.fetch("purchase_order_line_id")), shipped_quantity: line.fetch("quantity"))
        end)
    end
    private_class_method :accept, :receive_shipment
  end
end
