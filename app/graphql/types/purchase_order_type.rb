module Types
  # 発注側が所有する発注。相手の受注へたどるフィールドは持たず、還流した状況と写しだけを見せる
  class PurchaseOrderType < BaseObject
    graphql_name "PurchaseOrder"
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy

    field :id, ID, null: false
    field :order_no, String, null: false
    field :supplier, TenantType, null: false
    field :order_date, GraphQL::Types::ISO8601Date, null: false
    field :desired_delivery_on, GraphQL::Types::ISO8601Date
    field :status, PurchaseOrderStatusType, null: false
    field :cancellation_pending, Boolean, null: false, description: "回答待ちの取消依頼がある"
    field :total_amount, GraphQL::Types::BigInt, description: "税抜の合計金額。受注確定の前の明細を含むと空"
    field :lines, [ PurchaseOrderLineType ], null: false
    field :cancellation_requests, [ CancellationRequestType ], null: false
    field :inbound_shipments, [ InboundShipmentType ], null: false
    field :supplier_shipments, resolver: Resolvers::Buyer::SupplierShipmentsResolver,
      description: "経路 3。view_shipments が無ければ空"

    def supplier
      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :tenants, context[:current_user])
        .load(object.supplier_tenant_id)
    end

    def lines
      dataloader.with(Sources::PublicApiSource, Purchasing::PurchaseOrders, :lines_for, context[:current_user]).load(object.id)
    end

    def cancellation_requests
      dataloader.with(Sources::PublicApiSource, Purchasing::PurchaseOrders, :cancellation_requests_for, context[:current_user])
        .load(object.id)
    end

    def inbound_shipments
      dataloader.with(Sources::PublicApiSource, Purchasing::PurchaseOrders, :inbound_shipments_for, context[:current_user])
        .load(object.id)
    end
  end
end
