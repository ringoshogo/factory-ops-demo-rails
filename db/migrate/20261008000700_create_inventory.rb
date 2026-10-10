class CreateInventory < ActiveRecord::Migration[8.1]
  include TenantTable

  # 在庫・引当・在庫移動履歴（docs/architecture/data-model.md「在庫（`inventory`）」）。item_id・sales_order_line_id は受注の行の ID 参照
  def change
    create_tenant_table :stocks do |t|
      t.uuid :item_id, null: false
      t.integer :on_hand, null: false, default: 0
      t.integer :allocated, null: false, default: 0
      t.integer :safety_stock, null: false, default: 0
      t.timestamps

      # 引当と移動履歴の複合外部キーの参照先
      t.index [ :owner_tenant_id, :item_id ], unique: true
      # 有効在庫（on_hand - allocated）が負にならない
      t.check_constraint "allocated >= 0 AND on_hand >= allocated", name: "stocks_available_non_negative"
      t.check_constraint "safety_stock >= 0", name: "stocks_safety_stock_non_negative"
    end

    create_tenant_table :allocations do |t|
      t.uuid :sales_order_line_id, null: false
      t.uuid :item_id, null: false
      t.integer :quantity, null: false
      t.string :status, null: false, default: "active"
      t.timestamps

      t.index :sales_order_line_id, unique: true
      t.index [ :owner_tenant_id, :item_id ]
      t.check_constraint "quantity > 0", name: "allocations_quantity_positive"
      t.check_constraint "status::text IN ('active', 'released', 'consumed')", name: "allocations_status_check"
    end

    create_tenant_table :stock_movements do |t|
      t.uuid :item_id, null: false
      t.string :type, null: false
      t.integer :quantity, null: false
      t.string :reason
      t.uuid :allocation_id
      # 追記だけの表なので updated_at を持たない
      t.datetime :created_at, null: false

      t.index [ :owner_tenant_id, :item_id ]
      t.index [ :owner_tenant_id, :allocation_id ]
      t.check_constraint "quantity > 0", name: "stock_movements_quantity_positive"
      t.check_constraint "type::text IN ('inbound', 'outbound', 'allocate', 'deallocate', 'ship')", name: "stock_movements_type_check"
      # 引当を動かす移動だけが引当を指す
      t.check_constraint "(type::text IN ('allocate', 'deallocate', 'ship')) = (allocation_id IS NOT NULL)",
        name: "stock_movements_allocation_by_type"
    end

    safety_assured do
      add_foreign_key :allocations, :stocks, column: [ :owner_tenant_id, :item_id ], primary_key: [ :owner_tenant_id, :item_id ]
      add_foreign_key :stock_movements, :stocks, column: [ :owner_tenant_id, :item_id ], primary_key: [ :owner_tenant_id, :item_id ]
      # 入出庫の移動は allocation_id が空なので、空を許す複合外部キーにする
      add_foreign_key :stock_movements, :allocations, column: [ :owner_tenant_id, :allocation_id ],
        primary_key: [ :owner_tenant_id, :id ]
    end
  end
end
