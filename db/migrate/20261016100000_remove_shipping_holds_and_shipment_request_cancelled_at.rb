class RemoveShippingHoldsAndShipmentRequestCancelledAt < ActiveRecord::Migration[8.1]
  include TenantTable

  BILLABLE_ITEMS_COMMENT_BEFORE = "[請求] 請求対象明細。「請求対象確定」の写しで、請求書が空なら未請求".freeze
  # 請求対象明細は、受注が検収と同じトランザクションで請求の公開 API を呼んで書き、イベントの写しではない
  BILLABLE_ITEMS_COMMENT = "[請求] 請求対象明細。受注が検収で確定した明細で、請求書が空なら未請求".freeze

  # 出荷依頼の取消済と出荷停止中を、受注の公開 API の副問い合わせから導出するので、出荷停止の表と出荷依頼の取消の時刻を消す
  # （docs/adr/012-同じテナントの中の連結を同期にし出荷可能だけをイベントで残す.md）
  def up
    # 列を消すマイグレーションは、モデルの ignored_columns に列を入れた版と一緒に置く
    # （docs/guides/config.md「initializers/strong_migrations.rb：危険なマイグレーションを止める」）。表のモデルは消してある
    safety_assured do
      drop_table :shipping_holds
      remove_column :shipment_requests, :cancelled_at
    end
    change_table_comment :billable_items, from: BILLABLE_ITEMS_COMMENT_BEFORE, to: BILLABLE_ITEMS_COMMENT
  end

  # 表と列を空で戻す。値は戻さない。消した後の取消と審査は受注にしか残らず、受注から作り直す受け手も無いからである
  def down
    change_table_comment :billable_items, from: BILLABLE_ITEMS_COMMENT, to: BILLABLE_ITEMS_COMMENT_BEFORE
    add_column :shipment_requests, :cancelled_at, :datetime
    create_tenant_table :shipping_holds, comment: "[出荷] 出荷停止。取消の審査ごとに 1 件で、解除するまで受注の出荷指示と計上を止める" do |t|
      t.uuid :sales_order_id, null: false
      t.uuid :source_cancellation_review_id, null: false
      t.datetime :released_at
      t.timestamps

      t.index :source_cancellation_review_id, unique: true
      t.index :sales_order_id
    end
  end
end
