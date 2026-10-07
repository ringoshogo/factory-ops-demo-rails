module Purchasing
  # 受注側からのイベントの受け手。発注側テナントの名義で、自社の発注の時刻列と明細の写しだけを書く
  # （docs/architecture/data-model.md「イベントの受け口と冪等キー」）。取引関係の状態は見ない
  module SupplierEventReceiver
    def self.handle(event)
      order = PurchaseOrder.lock.find_by!(owner_tenant_id: Current.tenant_id, id: event.purchase_order_id,
        supplier_tenant_id: event.supplier_tenant_id)

      case event
      when Contracts::SalesOrderConfirmed then accept(order, event)
      when Contracts::PartMatchPending then order.update!(awaiting_match_at: Time.current) unless order.awaiting_match_at
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
    private_class_method :accept
  end
end
