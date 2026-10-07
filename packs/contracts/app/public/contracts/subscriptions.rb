module Contracts
  # 配送表。イベントごとに、受け手のクラス名と、宛先テナントを示すペイロードの項目を並べる。
  # 1 つのイベントが別のテナントの受け手へ届くことがあるので、宛先は受け手ごとに書く。
  # 受け手を文字列で書くので、contracts は受け手のパッケージに依存しない
  module Subscriptions
    Route = Data.define(:receiver, :tenant_key)

    # 例："Contracts::OrderPlaced" => [ Route.new(receiver: "Sales::OrderPlacedReceiver", tenant_key: "supplier_tenant_id") ]
    TABLE = {}.freeze

    def self.routes(event_name)
      TABLE.fetch(event_name) { raise KeyError, "配送表に無いイベント: #{event_name}" }
    end
  end
end
