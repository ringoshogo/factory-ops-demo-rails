class CreateSalesOrders < ActiveRecord::Migration[8.1]
  include TenantTable

  # 得意先品番の対応表・受注・受注明細と、受注番号の採番行（docs/architecture/data-model.md「テナントの持ち方」「受注」）
  def change
    # テナントごとに 1 行。受注を作るたびに行ロックして last_number を進める
    create_tenant_table :sales_order_sequences do |t|
      t.integer :last_number, null: false, default: 0
      t.timestamps

      t.index :owner_tenant_id, unique: true
    end

    create_tenant_table :customer_part_mappings do |t|
      t.uuid :customer_tenant_id, null: false
      t.string :customer_part_number, null: false
      t.timestamps

      t.index [ :owner_tenant_id, :customer_tenant_id, :customer_part_number ], unique: true,
        name: "index_customer_part_mappings_on_customer_part"
    end
    add_tenant_reference :customer_part_mappings, :items

    create_tenant_table :sales_orders do |t|
      t.string :order_no, null: false
      t.uuid :customer_tenant_id, null: false
      # 連結の冪等キー。同じ「発注登録」が 2 回届いても受注は 1 件
      t.uuid :source_purchase_order_id, null: false
      t.date :order_date, null: false
      t.date :due_date
      t.datetime :confirmed_at
      t.datetime :shipped_at
      t.datetime :inspected_at
      t.datetime :cancelled_at
      t.timestamps

      t.index [ :owner_tenant_id, :order_no ], unique: true
      t.index :source_purchase_order_id, unique: true
      t.index :customer_tenant_id
      t.check_constraint "cancelled_at IS NULL OR shipped_at IS NULL", name: "sales_orders_cancelled_or_shipped"
      t.check_constraint "inspected_at IS NULL OR shipped_at IS NOT NULL", name: "sales_orders_inspected_after_shipped"
    end

    create_tenant_table :sales_order_lines do |t|
      t.uuid :source_purchase_order_line_id, null: false
      t.string :customer_part_number, null: false
      # 照合前は空。照合すると品目と、品目名・単価・税率の写しが一緒に埋まる
      t.uuid :item_id
      t.string :item_name
      t.bigint :unit_price
      t.integer :tax_rate_percent
      t.integer :quantity, null: false
      t.timestamps

      t.index :source_purchase_order_line_id, unique: true
      t.index [ :owner_tenant_id, :item_id ]
      t.check_constraint "quantity > 0", name: "sales_order_lines_quantity_positive"
      t.check_constraint "(item_id IS NULL AND item_name IS NULL AND unit_price IS NULL AND tax_rate_percent IS NULL) OR " \
        "(item_id IS NOT NULL AND item_name IS NOT NULL AND unit_price IS NOT NULL AND tax_rate_percent IS NOT NULL)",
        name: "sales_order_lines_matched_together"
    end
    add_tenant_reference :sales_order_lines, :sales_orders
    # 照合前の明細は item_id が空なので、空を許す複合外部キーにする（空の行は検査されない）
    safety_assured do
      add_foreign_key :sales_order_lines, :items, column: [ :owner_tenant_id, :item_id ], primary_key: [ :owner_tenant_id, :id ]
    end
  end
end
