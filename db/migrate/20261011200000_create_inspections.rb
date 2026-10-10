class CreateInspections < ActiveRecord::Migration[8.1]
  include TenantTable

  # 入荷検収と、受注側の検収の記録（docs/architecture/data-model.md「購買（`purchasing`）」「受注（`sales`）」）。
  # inspection_records.shipment_id は出荷実績への ID 参照で、外部キーを張らない
  def change
    create_tenant_table :receipt_inspections, comment: "[購買] 入荷検収。入荷 1 件に 1 回で、検収日を持つ" do |t|
      t.date :inspected_on, null: false
      t.timestamps
    end
    add_tenant_reference :receipt_inspections, :inbound_shipments
    # 入荷 1 件に 1 回。2 回目の検収は公開 API が CONFLICT にし、この索引が最後に守る
    add_index :receipt_inspections, :inbound_shipment_id, unique: true

    create_tenant_table :receipt_inspection_lines, comment: "[購買] 入荷検収の明細。入荷の明細ごとの検収数量を持つ" do |t|
      t.integer :accepted_quantity, null: false
      t.timestamps

      # 0 は全量の不合格。出荷数量以下であることは、入荷の明細と照らして公開 API が確かめる
      t.check_constraint "accepted_quantity >= 0", name: "receipt_inspection_lines_accepted_quantity_not_negative"
    end
    add_tenant_reference :receipt_inspection_lines, :receipt_inspections
    add_tenant_reference :receipt_inspection_lines, :inbound_shipment_lines
    add_index :receipt_inspection_lines, :inbound_shipment_line_id, unique: true

    create_tenant_table :inspection_records, comment: "[受注] 検収の記録。「検収完了」の写しで、出荷実績と受注明細の組ごとに 1 行" do |t|
      t.uuid :shipment_id, null: false
      t.integer :quantity, null: false
      t.date :inspected_on, null: false
      t.timestamps

      t.check_constraint "quantity >= 0", name: "inspection_records_quantity_not_negative"
    end
    add_tenant_reference :inspection_records, :sales_order_lines
    # 「検収完了」の受注の冪等キー
    add_index :inspection_records, [ :shipment_id, :sales_order_line_id ], unique: true
  end
end
