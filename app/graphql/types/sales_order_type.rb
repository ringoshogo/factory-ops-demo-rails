module Types
  # 受注側が所有する受注。連結元の発注 ID など、相手側を指す ID はフィールドに出さない
  class SalesOrderType < BaseObject
    graphql_name "SalesOrder"
    perspective :supplier
    authorize_with Sales::SalesOrderPolicy

    field :id, ID, null: false
    field :order_no, String, null: false
    field :customer, TenantType, null: false
    field :order_date, GraphQL::Types::ISO8601Date, null: false
    field :due_date, GraphQL::Types::ISO8601Date
    field :status, SalesOrderStatusType, null: false
    field :cancellation_review_pending, Boolean, null: false, description: "未決の取消の審査がある"
    field :total_amount, GraphQL::Types::BigInt, description: "税抜の合計金額。品番照合待ちの明細を含むと空"
    field :lines, [ SalesOrderLineType ], null: false
    field :cancellation_reviews, [ CancellationReviewType ], null: false, description: "承認と却下に使う審査 ID を得る"
    field :shipment_request, ShipmentRequestType, description: "全量引当で出荷可能になった後に現れる"

    def customer
      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :tenants, context[:current_user])
        .load(object.customer_tenant_id)
    end

    def lines
      dataloader.with(Sources::PublicApiSource, Sales::SalesOrders, :lines_for, context[:current_user]).load(object.id)
    end

    def cancellation_reviews
      dataloader.with(Sources::PublicApiSource, Sales::CancellationReviews, :for_sales_orders, context[:current_user]).load(object.id)
    end

    # 受注は出荷に依存しないので、ルートパッケージで出荷の公開 API を呼ぶ
    def shipment_request
      dataloader.with(Sources::PublicApiSource, Fulfillment::ShipmentRequests, :for_sales_orders, context[:current_user])
        .load(object.id)
    end
  end
end
