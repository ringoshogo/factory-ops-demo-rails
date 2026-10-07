module Types
  # 経路 3 の出荷明細。SupplierShipment の中にだけ現れる。出荷明細 ID は返さず、自社の発注明細で識別する
  class SupplierShipmentLineType < BaseObject
    graphql_name "SupplierShipmentLine"
    perspective :buyer
    authorize_with Fulfillment::ShipmentRequestPolicy, :show_to_buyer?

    field :purchase_order_line, PurchaseOrderLineType, null: false
    field :quantity, Int, null: false

    # 出荷明細が持つ発注明細 ID の写しから、購買の公開 API で自社の発注明細を引く。受注明細や出荷依頼を経由しない
    def purchase_order_line
      dataloader.with(Sources::PublicApiSource, Purchasing::PurchaseOrders, :lines_by_id, context[:current_user])
        .load(object.purchase_order_line_id)
    end
  end
end
