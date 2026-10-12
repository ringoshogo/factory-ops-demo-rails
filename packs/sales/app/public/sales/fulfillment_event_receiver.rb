module Sales
  # 出荷からのイベントの受け手。受注側テナントの名義で、自社の受注の時刻列だけを書く
  # （docs/architecture/data-model.md「イベントの受け口と冪等キー」）。取引関係の状態は見ない。
  # イベントの受け手は操作者のいない入口なので、テナントの設定を求め、所有の条件を RLS に任せずに書き、値を返さない
  # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
  module FulfillmentEventReceiver
    def self.handle(event)
      Tenancy.require_tenant!
      case event
      when Contracts::ShipmentPosted then ship(event)
      else raise ArgumentError, "unexpected event: #{event.class}"
      end
      nil
    end

    # shipped_at が空のときだけ書く
    def self.ship(event)
      order = SalesOrder.lock.find_by!(owner_tenant_id: Current.tenant_id, id: event.sales_order_id,
        customer_tenant_id: event.buyer_tenant_id)
      order.update!(shipped_at: Time.current) unless order.shipped_at
    end
    private_class_method :ship
  end
end
