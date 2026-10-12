class RemoveUnitPriceFromItems < ActiveRecord::Migration[8.1]
  # 単価の正本を item_prices に移し終えた後に、items.unit_price を消し、受注明細の priced_on を照合後に埋まる列に加える
  # （docs/adr/006 決定 1、strong_migrations の列を消す手順）。sales:backfill_item_prices を流す前に流すと、値を失うので止まる
  def up
    remaining = select_value(<<~SQL)
      SELECT (SELECT count(*) FROM items i
              WHERE NOT EXISTS (SELECT 1 FROM item_prices p WHERE p.item_id = i.id AND upper_inf(p.recorded_period)))
           + (SELECT count(*) FROM sales_order_lines WHERE item_id IS NOT NULL AND priced_on IS NULL)
    SQL
    if remaining.positive?
      raise "現在の単価の行が無い品目か、priced_on の無い照合済みの明細が #{remaining} 件ある。先に bin/rails sales:backfill_item_prices を流す"
    end

    remove_check_constraint :sales_order_lines, name: "sales_order_lines_matched_together"
    # 既存の行はすべて条件を満たすことを上で確かめたので、表を検証しながら足す
    safety_assured do
      add_check_constraint :sales_order_lines,
        "(item_id IS NULL AND item_name IS NULL AND unit_price IS NULL AND priced_on IS NULL AND tax_rate_percent IS NULL) OR " \
        "(item_id IS NOT NULL AND item_name IS NOT NULL AND unit_price IS NOT NULL AND priced_on IS NOT NULL AND tax_rate_percent IS NOT NULL)",
        name: "sales_order_lines_matched_together"
      # Sales::Item は ignored_columns でこの列を読み書きしない
      remove_column :items, :unit_price, :bigint
    end
  end

  # 列には、いま信じている今日の単価を戻す（docs/adr/006「撤退コスト」）。今日はカタログと同じ Date.current で決め、
  # セッションの時刻帯で変わる SQL の CURRENT_DATE は使わない（docs/adr/006 決定 6）
  def down
    add_column :items, :unit_price, :bigint
    execute <<~SQL
      UPDATE items i SET unit_price = p.unit_price FROM item_prices p
      WHERE p.item_id = i.id AND upper_inf(p.recorded_period) AND p.valid_period @> #{connection.quote(Date.current)}::date
    SQL
    remove_check_constraint :sales_order_lines, name: "sales_order_lines_matched_together"
    safety_assured do
      add_check_constraint :sales_order_lines,
        "(item_id IS NULL AND item_name IS NULL AND unit_price IS NULL AND tax_rate_percent IS NULL) OR " \
        "(item_id IS NOT NULL AND item_name IS NOT NULL AND unit_price IS NOT NULL AND tax_rate_percent IS NOT NULL)",
        name: "sales_order_lines_matched_together"
    end
  end
end
