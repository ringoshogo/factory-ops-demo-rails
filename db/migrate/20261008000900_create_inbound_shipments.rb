class CreateInboundShipments < ActiveRecord::Migration[8.1]
  include TenantTable

  # 購買が持つ「出荷計上」の写しと、読む経路 3（docs/architecture/data-model.md「購買」「RLS」）。
  # inbound_shipments.shipment_id は受注側テナントの出荷実績の ID 参照
  def change
    create_tenant_table :inbound_shipments do |t|
      t.uuid :shipment_id, null: false
      t.date :shipped_on, null: false
      t.timestamps

      # 「出荷計上」の購買の冪等キー
      t.index :shipment_id, unique: true
    end
    add_tenant_reference :inbound_shipments, :purchase_orders

    create_tenant_table :inbound_shipment_lines do |t|
      t.integer :shipped_quantity, null: false
      t.timestamps

      t.check_constraint "shipped_quantity > 0", name: "inbound_shipment_lines_shipped_quantity_positive"
    end
    add_tenant_reference :inbound_shipment_lines, :inbound_shipments
    add_tenant_reference :inbound_shipment_lines, :purchase_order_lines
    add_index :inbound_shipment_lines, [ :inbound_shipment_id, :purchase_order_line_id ], unique: true

    # 経路 3：自社の発注に連結した出荷。view_shipments の付与はアプリの policy scope が判定する
    add_partner_read_policy :shipments,
      using: "buyer_tenant_id = current_tenant_id() AND partnership_active(owner_tenant_id, buyer_tenant_id)"
    add_partner_read_policy :shipment_lines, using: "EXISTS (SELECT 1 FROM shipments s WHERE s.id = shipment_lines.shipment_id)"
  end
end
