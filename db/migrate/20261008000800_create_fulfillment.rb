class CreateFulfillment < ActiveRecord::Migration[8.1]
  include TenantTable

  # 出荷依頼・出荷指示・出荷実績（docs/architecture/data-model.md「出荷」）。
  # sales_order_id・sales_order_line_id・item_id は受注の行の、buyer_tenant_id・source_purchase_order_* は相手テナントの ID 参照
  def change
    create_tenant_table :shipment_requests do |t|
      t.uuid :sales_order_id, null: false
      t.uuid :buyer_tenant_id, null: false
      t.uuid :source_purchase_order_id, null: false
      t.date :due_date
      t.datetime :cancelled_at
      t.timestamps

      # 「出荷可能」の冪等キー
      t.index :sales_order_id, unique: true
    end

    create_tenant_table :shipment_request_lines do |t|
      t.uuid :sales_order_line_id, null: false
      t.uuid :source_purchase_order_line_id, null: false
      t.uuid :item_id, null: false
      t.integer :quantity, null: false
      t.timestamps

      t.index :sales_order_line_id, unique: true
      t.check_constraint "quantity > 0", name: "shipment_request_lines_quantity_positive"
    end
    add_tenant_reference :shipment_request_lines, :shipment_requests

    create_tenant_table :shipping_instructions do |t|
      t.date :planned_date, null: false
      t.string :status, null: false, default: "active"
      t.timestamps

      t.check_constraint "status::text IN ('active', 'cancelled')", name: "shipping_instructions_status_check"
    end
    add_tenant_reference :shipping_instructions, :shipment_requests
    # 有効な出荷指示は出荷依頼ごとに 1 件
    add_index :shipping_instructions, :shipment_request_id, unique: true, where: "status = 'active'",
      name: "index_shipping_instructions_one_active_per_request"

    create_tenant_table :shipments do |t|
      t.uuid :buyer_tenant_id, null: false
      t.uuid :source_purchase_order_id, null: false
      t.date :shipped_on, null: false
      t.timestamps
    end
    add_tenant_reference :shipments, :shipping_instructions
    add_tenant_reference :shipments, :shipment_requests
    # 分納しないので、出荷依頼ごとに 1 件
    add_index :shipments, :shipment_request_id, unique: true

    create_tenant_table :shipment_lines do |t|
      t.uuid :source_purchase_order_line_id, null: false
      t.integer :quantity, null: false
      t.timestamps

      t.check_constraint "quantity > 0", name: "shipment_lines_quantity_positive"
    end
    add_tenant_reference :shipment_lines, :shipments
    add_tenant_reference :shipment_lines, :shipment_request_lines
    add_index :shipment_lines, :shipment_request_line_id, unique: true
  end
end
