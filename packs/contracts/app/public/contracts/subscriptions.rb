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
      # 受け手の出荷は M13 で足す（docs/implementation-plan.md）
      "Contracts::SalesOrderReadyForShipment" => []
    }.freeze

    def self.routes(event_name)
      TABLE.fetch(event_name) { raise KeyError, "配送表に無いイベント: #{event_name}" }
    end
  end
end
