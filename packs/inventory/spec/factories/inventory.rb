FactoryBot.define do
  # どれも Tenancy.with_tenant の中で作る。item_id は受注の品目の ID 参照で、外部キーを張らない
  factory :stock, class: "Inventory::Stock" do
    owner_tenant_id { Current.tenant_id }
    item_id { SecureRandom.uuid }
    on_hand { 10 }
  end

  factory :allocation, class: "Inventory::StockAllocation" do
    owner_tenant_id { Current.tenant_id }
    sales_order_line_id { SecureRandom.uuid }
    item_id { FactoryBot.create(:stock, owner_tenant_id:, allocated: quantity).item_id }
    quantity { 1 }
  end

  factory :stock_movement, class: "Inventory::StockMovement" do
    owner_tenant_id { Current.tenant_id }
    item_id { FactoryBot.create(:stock, owner_tenant_id:).item_id }
    type { "inbound" }
    quantity { 10 }
  end
end
