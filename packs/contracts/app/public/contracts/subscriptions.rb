module Contracts
  # 配送表。イベントごとに、受け手のクラス名と、宛先テナントを示すペイロードの項目を並べる。
  # 1 つのイベントが別のテナントの受け手へ届くことがあるので、宛先は受け手ごとに書く。
  # 受け手を文字列で書くので、contracts は受け手のパッケージに依存しない
  module Subscriptions
    Route = Data.define(:receiver, :tenant_key)

    TABLE = {
      "Contracts::PurchaseOrderPlaced" => [ Route.new(receiver: "Sales::PurchaseOrderTranslator", tenant_key: "supplier_tenant_id") ],
      "Contracts::SalesOrderConfirmed" => [ Route.new(receiver: "Purchasing::SupplierEventReceiver", tenant_key: "buyer_tenant_id") ],
      "Contracts::PartMatchPending" => [ Route.new(receiver: "Purchasing::SupplierEventReceiver", tenant_key: "buyer_tenant_id") ],
      "Contracts::SalesOrderReadyForShipment" => [ Route.new(receiver: "Fulfillment::SalesEventReceiver", tenant_key: "supplier_tenant_id") ],
      "Contracts::CancellationRequested" => [ Route.new(receiver: "Sales::PurchasingEventReceiver", tenant_key: "supplier_tenant_id") ],
      "Contracts::CancellationApproved" => [ Route.new(receiver: "Purchasing::SupplierEventReceiver", tenant_key: "buyer_tenant_id") ],
      "Contracts::CancellationRejected" => [ Route.new(receiver: "Purchasing::SupplierEventReceiver", tenant_key: "buyer_tenant_id") ],
      "Contracts::SalesOrderCancelled" => [ Route.new(receiver: "Purchasing::SupplierEventReceiver", tenant_key: "buyer_tenant_id") ],
      "Contracts::ShippingHeld" => [ Route.new(receiver: "Fulfillment::SalesEventReceiver", tenant_key: "supplier_tenant_id") ],
      "Contracts::ShippingHoldReleased" => [ Route.new(receiver: "Fulfillment::SalesEventReceiver", tenant_key: "supplier_tenant_id") ],
      "Contracts::ShipmentCancelled" => [ Route.new(receiver: "Fulfillment::SalesEventReceiver", tenant_key: "supplier_tenant_id") ],
      "Contracts::ReceiptInspected" => [ Route.new(receiver: "Sales::PurchasingEventReceiver", tenant_key: "supplier_tenant_id") ],
      "Contracts::BillableItemConfirmed" => [ Route.new(receiver: "Billing::SalesEventReceiver", tenant_key: "supplier_tenant_id") ],
      "Contracts::InvoiceIssued" => [ Route.new(receiver: "Purchasing::BillingEventReceiver", tenant_key: "buyer_tenant_id") ],
      "Contracts::ShipmentPosted" => [
        Route.new(receiver: "Sales::FulfillmentEventReceiver", tenant_key: "supplier_tenant_id"),
        Route.new(receiver: "Purchasing::SupplierEventReceiver", tenant_key: "buyer_tenant_id")
      ]
    }.freeze

    def self.routes(event_name)
      TABLE.fetch(event_name) { raise KeyError, "配送表に無いイベント: #{event_name}" }
    end
  end
end
