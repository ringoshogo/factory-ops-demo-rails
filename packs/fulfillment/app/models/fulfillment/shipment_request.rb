module Fulfillment
  # 出荷依頼（「出荷可能」の写し）。sales_order_id は受注の行の、buyer_tenant_id・source_purchase_order_id は相手テナントの
  # ID 参照で、関連を張らない
  class ShipmentRequest < TenantRecord
    has_many :lines, -> { order(:id) }, class_name: "Fulfillment::ShipmentRequestLine", inverse_of: :shipment_request
    has_many :instructions, class_name: "Fulfillment::ShippingInstruction", inverse_of: :shipment_request
    has_one :shipment, class_name: "Fulfillment::Shipment", inverse_of: :shipment_request

    # 同じ受注に解除されていない出荷停止がある。出荷停止の受け手は出荷依頼の行をロックしてから停止を書くので、
    # 出荷依頼の行をロックした後に読めば、計上と出荷指示の作成の途中で停止が割り込まない
    def held? = ShippingHold.active.exists?(sales_order_id:)
  end
end
