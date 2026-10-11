module Types
  # 発注側が所有する受領請求書（「請求書発行」の写し）。受注側の請求書 ID は返さない
  class ReceivedInvoiceType < BaseObject
    graphql_name "ReceivedInvoice"
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy

    field :id, ID, null: false
    field :invoice_number, String, null: false
    field :supplier, TenantType, null: false
    field :period_start, GraphQL::Types::ISO8601Date, null: false
    field :period_end, GraphQL::Types::ISO8601Date, null: false
    field :issued_on, GraphQL::Types::ISO8601Date, null: false
    field :subtotal, GraphQL::Types::BigInt, null: false
    field :tax_total, GraphQL::Types::BigInt, null: false
    field :total, GraphQL::Types::BigInt, null: false
    field :lines, [ ReceivedInvoiceLineType ], null: false

    def supplier
      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :tenants, context[:current_user])
        .load(object.supplier_tenant_id)
    end

    def lines
      dataloader.with(Sources::PublicApiSource, Purchasing::ReceivedInvoices, :lines_for, context[:current_user]).load(object.id)
    end
  end
end
