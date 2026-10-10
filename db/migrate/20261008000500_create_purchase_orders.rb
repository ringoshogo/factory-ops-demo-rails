class CreatePurchaseOrders < ActiveRecord::Migration[8.1]
  include TenantTable

  # 発注・発注明細と、発注番号の採番行（docs/architecture/data-model.md「テナントの持ち方」「購買（`purchasing`）」）
  def change
    # テナントごとに 1 行。発注を登録するたびに行ロックして last_number を進める
    create_tenant_table :purchase_order_sequences do |t|
      t.integer :last_number, null: false, default: 0
      t.timestamps

      t.index :owner_tenant_id, unique: true
    end

    create_tenant_table :purchase_orders do |t|
      t.string :order_no, null: false
      t.uuid :supplier_tenant_id, null: false
      t.date :order_date, null: false
      t.date :desired_delivery_on
      t.datetime :awaiting_match_at
      t.datetime :accepted_at
      t.datetime :cancelled_at
      t.datetime :supplier_cancelled_at
      t.timestamps

      t.index [ :owner_tenant_id, :order_no ], unique: true
      t.index :supplier_tenant_id
      t.check_constraint "cancelled_at IS NULL OR supplier_cancelled_at IS NULL", name: "purchase_orders_single_cancellation"
    end

    create_tenant_table :purchase_order_lines do |t|
      t.string :part_number, null: false
      t.integer :quantity, null: false
      t.string :confirmed_item_name
      t.bigint :confirmed_unit_price
      t.timestamps

      t.check_constraint "quantity > 0", name: "purchase_order_lines_quantity_positive"
      t.check_constraint "(confirmed_item_name IS NULL) = (confirmed_unit_price IS NULL)",
        name: "purchase_order_lines_confirmed_together"
    end
    add_tenant_reference :purchase_order_lines, :purchase_orders
    add_index :purchase_order_lines, [ :purchase_order_id, :part_number ], unique: true
  end
end
