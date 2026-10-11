module Types
  # 受領請求書の明細。ReceivedInvoice の中にだけ現れ、自社の発注明細で識別する
  class ReceivedInvoiceLineType < BaseObject
    graphql_name "ReceivedInvoiceLine"
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy

    field :purchase_order_line, PurchaseOrderLineType, null: false
    field :item_name, String, null: false
    field :unit_price, GraphQL::Types::BigInt, null: false
    field :quantity, Int, null: false
    field :tax_rate_percent, Int, null: false
    field :amount, GraphQL::Types::BigInt, null: false

    def purchase_order_line
      dataloader.with(Sources::PublicApiSource, Purchasing::PurchaseOrders, :lines_by_id, context[:current_user])
        .load(object.purchase_order_line_id)
    end
  end
end
