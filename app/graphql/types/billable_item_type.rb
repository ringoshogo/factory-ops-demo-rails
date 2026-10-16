module Types
  # 受注側が所有する請求対象明細（受注が検収で確定した明細）。連結元の発注明細 ID はフィールドに出さない
  class BillableItemType < BaseObject
    graphql_name "BillableItem"
    perspective :supplier
    authorize_with Billing::InvoicePolicy

    field :id, ID, null: false
    field :customer, TenantType, null: false
    field :sales_order_line, SalesOrderLineType, null: false
    field :item_name, String, null: false
    field :unit_price, GraphQL::Types::BigInt, null: false
    field :quantity, Int, null: false, description: "検収数量"
    field :tax_rate_percent, Int, null: false
    field :amount, GraphQL::Types::BigInt, null: false, description: "単価 × 検収数量。税を含まない"
    field :inspected_on, GraphQL::Types::ISO8601Date, null: false
    field :price_explanation, PriceExplanationType, null: false,
      description: "請求書の単価の説明。下書きの請求書と未請求の明細では、発行時の単価は空"

    def customer
      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :tenants, context[:current_user]).load(object.customer_tenant_id)
    end

    # 請求は受注に依存しないので、ルートパッケージで受注の公開 API を呼ぶ
    def sales_order_line
      dataloader.with(Sources::PublicApiSource, Sales::SalesOrders, :lines_by_ids, context[:current_user]).load(object.sales_order_line_id)
    end

    # 発行の時点の単価は、請求書の発行時刻を記録時点にして引く。請求書ごとに発行時刻が違うので、発行時刻ごとにまとめて引く
    # （docs/adr/006 決定 5）
    def price_explanation
      actor = context[:current_user]
      issued_at = object.invoice_id && dataloader.with(Sources::PublicApiSource, Billing::Invoices, :by_ids, actor).load(object.invoice_id).issued_at
      dataloader.with(Sources::PublicApiSource, Sales::ItemPrices, :explain, actor, as_of: issued_at).load(object.sales_order_line_id)
    end
  end
end
