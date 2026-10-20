class AddSalesOrderNoToShipmentRequests < ActiveRecord::Migration[8.1]
  # 出荷依頼の一覧を受注番号で並べるための、受注番号の写し（docs/architecture/data-model.md「出荷（`fulfillment`）」、docs/adr/011）。
  # 「出荷可能」のイベントで運んだ値を写す（docs/adr/011 決定 2）。既存の DB の写しは埋めない。
  # マイグレーションの後に bin/rails read_models:rebuild を流す（docs/adr/001 決定 4）
  def change
    add_column :shipment_requests, :sales_order_no, :string
  end
end
