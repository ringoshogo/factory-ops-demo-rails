module Fulfillment
  # 出荷依頼（「出荷可能」の写し）。sales_order_id は受注の行の、buyer_tenant_id・source_purchase_order_id は相手テナントの
  # ID 参照で、関連を張らない
  class ShipmentRequest < TenantRecord
    # 出荷依頼の取消済を受注の取消から導出するようにして消した列。消すマイグレーションの前に動いているプロセスが列を読み書きしないよう、
    # 列を消す前から無視する（strong_migrations の列を消す手順）
    self.ignored_columns += [ "cancelled_at" ]

    has_many :lines, -> { order(:id) }, class_name: "Fulfillment::ShipmentRequestLine", inverse_of: :shipment_request
    has_many :instructions, class_name: "Fulfillment::ShippingInstruction", inverse_of: :shipment_request
    has_one :shipment, class_name: "Fulfillment::Shipment", inverse_of: :shipment_request
  end
end
