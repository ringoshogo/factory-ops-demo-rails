module Types
  # 受注側が所有する出荷依頼（「出荷可能」の写し）。連結元の発注 ID はフィールドに出さない。
  # 受注へのフィールドは、ルートパッケージで受注の公開 API を呼んで解決する
  class ShipmentRequestType < BaseObject
    graphql_name "ShipmentRequest"
    perspective :supplier
    authorize_with Fulfillment::ShipmentRequestPolicy

    field :id, ID, null: false
    field :sales_order, SalesOrderType, null: false
    field :customer, TenantType, null: false
    field :due_date, GraphQL::Types::ISO8601Date
    field :status, ShipmentRequestStatusType, null: false
    field :lines, [ ShipmentRequestLineType ], null: false
    field :instruction, ShippingInstructionType, description: "有効な出荷指示。無ければ空"
    field :shipment, ShipmentType

    def sales_order = load_from(Sales::SalesOrders, :by_ids, object.sales_order_id)
    def customer = load_from(Partnerships::Directory, :tenants, object.buyer_tenant_id)
    def lines = load_from(Fulfillment::ShipmentRequests, :lines_for, object.id)
    def instruction = load_from(Fulfillment::ShipmentRequests, :instructions_for, object.id)
    def shipment = load_from(Fulfillment::ShipmentRequests, :shipments_for, object.id)

    private

    def load_from(api, method, id) = dataloader.with(Sources::PublicApiSource, api, method, context[:current_user]).load(id)
  end
end
