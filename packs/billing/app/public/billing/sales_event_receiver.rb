module Billing
  # 受注からの「請求対象確定」の受け手（docs/architecture/context-map.md「検収と請求の流れ」4）。
  # 受注側テナントの名義で、未請求の請求対象明細を書く。取引関係の状態は見ない。
  # 締めのロック（請求条件の行）は取らないので、締めの最中に届いた明細は未請求のまま残り、次の締めで集まる。
  # イベントの受け手は操作者のいない入口なので、テナントの設定を求め、所有の条件を RLS に任せずに書き、値を返さない
  # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
  module SalesEventReceiver
    def self.handle(event)
      Tenancy.require_tenant!
      case event
      when Contracts::BillableItemConfirmed then record(event)
      else raise ArgumentError, "unexpected event: #{event.class}"
      end
      nil
    end

    # 冪等キーは出荷実績 ID と受注明細 ID の組で、行があれば（請求済みでも）何もしない。同時に届いた配送は一意索引が止める
    def self.record(event)
      BillableItem.insert({ owner_tenant_id: Current.tenant_id, customer_tenant_id: event.buyer_tenant_id,
        shipment_id: event.shipment_id, sales_order_line_id: event.sales_order_line_id,
        source_purchase_order_line_id: event.purchase_order_line_id, item_name: event.item_name, unit_price: Integer(event.unit_price, 10),
        quantity: event.quantity, tax_rate_percent: event.tax_rate_percent, inspected_on: Date.iso8601(event.inspected_on) },
        unique_by: %i[shipment_id sales_order_line_id])
    end
    private_class_method :record
  end
end
