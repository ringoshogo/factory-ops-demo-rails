module Types
  # 受注側のダッシュボード（docs/architecture/graphql-schema.md「読み取りの一覧」）。各フィールドは選ばれたときだけ公開 API を呼ぶ
  class SupplierDashboardType < BaseObject
    graphql_name "SupplierDashboard"
    perspective :supplier
    authorization_exempt reason: "自社の集計の入れ物。リゾルバが規則を評価し、各フィールドは自社の scope を掛けた公開 API の値を返す。" \
      "在庫と出荷依頼は、それぞれの型が規則を評価する"

    Dashboard = Data.define(:business_date)

    DUE_SOON_DAYS = 7
    STOCKS_LIMIT = 100

    field :business_date, GraphQL::Types::ISO8601Date, null: false, description: "集計の基準にした今日（Asia/Tokyo）"
    field :sales_order_counts, [ SalesOrderStatusCountType ], null: false, description: "受注の 7 つの状況ごとの件数。0 件の状況も返す"
    field :stocks_below_safety_stock, [ StockType ], null: false,
      description: "有効在庫が安全在庫より小さい在庫。品目コードの昇順で最大 100 件"
    field :shipment_requests_due_soon, [ ShipmentRequestType ], null: false,
      description: "出荷期限が今日から 7 日以内の、出荷も取消もしていない出荷依頼。期限の昇順で最大 100 件"
    field :unbilled_total, GraphQL::Types::BigInt, null: false, description: "未請求の請求対象明細の、単価 × 検収数量の合計（税抜き）"

    def sales_order_counts = Sales::SalesOrders.count_by_status(actor).map { |status, count| { status:, count: } }

    # 在庫は品目コードを持たないので、品目の公開 API で引いたコードで並べてから上限で切る。在庫の行は自社の品目にだけでき、
    # 品目は消さないので、どの在庫にも品目がある。品目は Stock.item と同じソースで引くので、Stock.item は同じ実行の中で引き直さない
    def stocks_below_safety_stock
      stocks = Inventory::Stocks.below_safety_stock(actor)
      items = dataloader.with(Sources::PublicApiSource, Sales::Catalog, :items_for, actor).load_all(stocks.map(&:item_id))
      stocks.zip(items).sort_by { |stock, item| [ item.code, stock.item_id ] }.first(STOCKS_LIMIT).map(&:first)
    end

    def shipment_requests_due_soon
      Fulfillment::ShipmentRequests.due_within(actor, today: object.business_date, days: DUE_SOON_DAYS)
    end

    def unbilled_total = Billing::BillableItems.unbilled_total(actor)

    private

    def actor = context[:current_user]
  end
end
