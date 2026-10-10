FactoryBot.define do
  # どれも Tenancy.with_tenant の中で、受注側のテナントで作る。受注の行と相手テナントの発注は ID で参照するだけなので、作らない
  factory :shipment_request, class: "Fulfillment::ShipmentRequest" do
    owner_tenant_id { Current.tenant_id }
    sales_order_id { SecureRandom.uuid }
    buyer_tenant_id { FactoryBot.create(:tenant).id }
    source_purchase_order_id { SecureRandom.uuid }
  end

  factory :shipment_request_line, class: "Fulfillment::ShipmentRequestLine" do
    owner_tenant_id { Current.tenant_id }
    shipment_request { association :shipment_request, owner_tenant_id: }
    sales_order_line_id { SecureRandom.uuid }
    source_purchase_order_line_id { SecureRandom.uuid }
    item_id { SecureRandom.uuid }
    quantity { 1 }
  end

  factory :shipping_instruction, class: "Fulfillment::ShippingInstruction" do
    owner_tenant_id { Current.tenant_id }
    shipment_request { association :shipment_request, owner_tenant_id: }
    planned_date { Date.current }
  end

  factory :shipment, class: "Fulfillment::Shipment" do
    owner_tenant_id { Current.tenant_id }
    shipping_instruction { association :shipping_instruction, owner_tenant_id: }
    shipment_request { shipping_instruction.shipment_request }
    buyer_tenant_id { shipment_request.buyer_tenant_id }
    source_purchase_order_id { shipment_request.source_purchase_order_id }
    shipped_on { Date.current }
  end

  factory :shipment_line, class: "Fulfillment::ShipmentLine" do
    owner_tenant_id { Current.tenant_id }
    shipment { association :shipment, owner_tenant_id: }
    shipment_request_line { association :shipment_request_line, owner_tenant_id:, shipment_request: shipment.shipment_request }
    source_purchase_order_line_id { shipment_request_line.source_purchase_order_line_id }
    quantity { shipment_request_line.quantity }
  end

  # 既定は解除前の停止
  factory :shipping_hold, class: "Fulfillment::ShippingHold" do
    owner_tenant_id { Current.tenant_id }
    sales_order_id { SecureRandom.uuid }
    source_cancellation_review_id { SecureRandom.uuid }
  end
end
