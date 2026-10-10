class CreateBilling < ActiveRecord::Migration[8.1]
  include TenantTable

  # 請求条件・請求対象明細・請求書・税率ごとの集計（docs/architecture/data-model.md「請求（`billing`）」）。
  # customer_tenant_id・shipment_id・sales_order_line_id・source_purchase_order_line_id はコンテキストか
  # テナントをまたぐ ID 参照で、外部キーを張らない
  def change
    create_tenant_table :billing_terms, comment: "[請求] 請求条件。取引先ごとの締め日で、31 は月末を表す" do |t|
      t.uuid :customer_tenant_id, null: false
      t.integer :closing_day, null: false
      t.timestamps

      # 締めはこの行をロックして、同じ取引先の締めと下書きの破棄を直列にする
      t.index [ :owner_tenant_id, :customer_tenant_id ], unique: true
      # 29・30 を許すと、2 月などの締め日が無い月が出る。月末締めは 31 で表す
      t.check_constraint "closing_day BETWEEN 1 AND 28 OR closing_day = 31", name: "billing_terms_closing_day_check"
    end

    create_tenant_table :invoices, comment: "[請求] 請求書。発行の時刻が空なら下書きで、請求番号は確定で振る" do |t|
      t.uuid :customer_tenant_id, null: false
      t.string :invoice_number
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.datetime :issued_at
      t.bigint :subtotal, null: false
      t.bigint :tax_total, null: false
      t.bigint :total, null: false
      t.timestamps

      # 請求番号は空の下書きどうしでぶつからない（NULL は一意索引で区別される）
      t.index [ :owner_tenant_id, :invoice_number ], unique: true
      # 下書きは取引先ごとに 1 件。締めは請求条件の行ロックの下で下書きの有無を確かめ、この索引が最後に守る
      t.index [ :owner_tenant_id, :customer_tenant_id ], unique: true, where: "issued_at IS NULL",
        name: "index_invoices_one_draft_per_customer"
      # 番号を振らずに確定した請求書と、番号を振った下書きを作らせない
      t.check_constraint "(issued_at IS NULL) = (invoice_number IS NULL)", name: "invoices_number_with_issue"
      t.check_constraint "period_start <= period_end", name: "invoices_period_order"
      t.check_constraint "subtotal >= 0 AND tax_total >= 0", name: "invoices_amounts_not_negative"
      t.check_constraint "total = subtotal + tax_total", name: "invoices_total_sum"
    end

    create_tenant_table :billable_items, comment: "[請求] 請求対象明細。「請求対象確定」の写しで、請求書が空なら未請求" do |t|
      t.uuid :customer_tenant_id, null: false
      t.uuid :shipment_id, null: false
      t.uuid :sales_order_line_id, null: false
      t.uuid :source_purchase_order_line_id, null: false
      t.string :item_name, null: false
      t.bigint :unit_price, null: false
      t.integer :quantity, null: false
      t.integer :tax_rate_percent, null: false
      t.date :inspected_on, null: false
      t.uuid :invoice_id
      t.timestamps

      # 「請求対象確定」の冪等キー
      t.index [ :shipment_id, :sales_order_line_id ], unique: true
      # 締めが取引先の未請求明細を集める
      t.index [ :owner_tenant_id, :customer_tenant_id, :inspected_on ], where: "invoice_id IS NULL",
        name: "index_billable_items_unbilled"
      t.index [ :owner_tenant_id, :invoice_id ]
      # 検収数量が 0 の明細は請求する額が無いので、受注は「請求対象確定」を出さない
      t.check_constraint "quantity > 0", name: "billable_items_quantity_positive"
      t.check_constraint "unit_price >= 0", name: "billable_items_unit_price_not_negative"
      t.check_constraint "tax_rate_percent = ANY (ARRAY[8, 10])", name: "billable_items_tax_rate_percent_check"
    end
    # 請求書は同じコンテキストの親なので、所有テナントの食い違いを複合外部キーで止める。未請求の明細は請求書が空で、
    # 外部キーは空の行を確かめない（MATCH SIMPLE）。新しい表には検証する行が無いので、検証付きの外部キーを許す
    safety_assured do
      add_foreign_key :billable_items, :invoices, column: [ :owner_tenant_id, :invoice_id ], primary_key: [ :owner_tenant_id, :id ]
    end

    create_tenant_table :invoice_tax_summaries, comment: "[請求] 請求書の税率ごとの課税対象額と、1 回だけ切り捨てた税額" do |t|
      t.integer :tax_rate_percent, null: false
      t.bigint :taxable_amount, null: false
      t.bigint :tax_amount, null: false
      t.timestamps

      t.check_constraint "tax_rate_percent = ANY (ARRAY[8, 10])", name: "invoice_tax_summaries_tax_rate_percent_check"
      t.check_constraint "taxable_amount >= 0 AND tax_amount >= 0", name: "invoice_tax_summaries_amounts_not_negative"
    end
    add_tenant_reference :invoice_tax_summaries, :invoices
    add_index :invoice_tax_summaries, [ :invoice_id, :tax_rate_percent ], unique: true
  end
end
