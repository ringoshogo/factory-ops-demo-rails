# 表の行列の期待値。テナントの表はすべてここに行を持つ。行の無い表があれば spec/matrix/table_matrix_spec.rb が落ちる。
# 書き込みに期待値は無い。どの表も、相手の名義で書けず、相手の行を変えられない
module MatrixExpectations
  OWNER_ONLY = {}.freeze

  # アプリのロールに UPDATE・DELETE の権限が無い表。相手の行にも自社の行にも、書き換えは権限で拒まれる
  APPEND_ONLY = %w[audit_logs].freeze

  # 表 => { 読むペルソナ => { 所有者のペルソナ => 見える件数 } }。自社の行は常に読めるので書かない。
  # 所有者以外に見せるのは読む 3 経路の表だけ（docs/architecture/context-map.md「テナントと所有」）
  TABLES = {
    "users" => OWNER_ONLY,
    # 経路 1。有効な取引関係の発注側に公開品目だけが見え、失効すると閉じる。
    # view_catalog の付与はアプリの policy scope が判定するので、付与の無い発注側にも RLS は見せる
    "items" => {
      granted_buyer: { supplier: 1 },
      ungranted_buyer: { supplier: 1 }
    },
    # 経路 2。有効な取引関係の発注側にだけ見え、失効すると権限付与ごと閉じる
    "partnerships" => {
      granted_buyer: { supplier: 1 },
      ungranted_buyer: { supplier: 1 }
    },
    "partnership_grants" => {
      granted_buyer: { supplier: 3 }
    },
    # 発注と受注はイベントだけで連結し、相手から読む経路は無い。世界の連結した組も相手には見えない。採番の表と対応表も同じ
    "purchase_orders" => OWNER_ONLY,
    "purchase_order_lines" => OWNER_ONLY,
    "purchase_order_sequences" => OWNER_ONLY,
    # 取消依頼と取消の審査はイベントだけで連結し、相手から読む経路は無い
    "cancellation_requests" => OWNER_ONLY,
    "cancellation_reviews" => OWNER_ONLY,
    "sales_orders" => OWNER_ONLY,
    "sales_order_lines" => OWNER_ONLY,
    "sales_order_sequences" => OWNER_ONLY,
    "customer_part_mappings" => OWNER_ONLY,
    # 在庫は受注側だけが所有し、相手から読む経路は無い
    "stocks" => OWNER_ONLY,
    "allocations" => OWNER_ONLY,
    "stock_movements" => OWNER_ONLY,
    # 出荷は受注側だけが所有する。出荷依頼・出荷停止・出荷指示は相手から読めない
    "shipment_requests" => OWNER_ONLY,
    "shipment_request_lines" => OWNER_ONLY,
    "shipping_instructions" => OWNER_ONLY,
    "shipping_holds" => OWNER_ONLY,
    # 経路 3。有効な取引関係の発注側に、自社の発注に連結した出荷だけが見え、付与があっても失効で閉じる。
    # view_shipments の付与はアプリの policy scope が判定するので、付与の無い発注側にも RLS は見せる
    "shipments" => {
      granted_buyer: { supplier: 1 },
      ungranted_buyer: { supplier: 1 }
    },
    "shipment_lines" => {
      granted_buyer: { supplier: 1 },
      ungranted_buyer: { supplier: 1 }
    },
    # 入荷は発注側だけが所有する「出荷計上」の写しで、受注側から読む経路は無い
    "inbound_shipments" => OWNER_ONLY,
    "inbound_shipment_lines" => OWNER_ONLY,
    # 検収は発注側だけが所有し、受注側へは「検収完了」で写す。受注側の検収の記録も発注側から読む経路は無い
    "receipt_inspections" => OWNER_ONLY,
    "receipt_inspection_lines" => OWNER_ONLY,
    "inspection_records" => OWNER_ONLY,
    # 請求は受注側だけが所有する。発注側へは「請求書発行」の写しで渡し、請求の行を読む経路は無い
    "billing_terms" => OWNER_ONLY,
    "billable_items" => OWNER_ONLY,
    "invoices" => OWNER_ONLY,
    "invoice_tax_summaries" => OWNER_ONLY,
    "invoice_sequences" => OWNER_ONLY,
    # 受領請求書は発注側だけが所有する「請求書発行」の写しで、受注側から読む経路は無い
    "received_invoices" => OWNER_ONLY,
    "received_invoice_lines" => OWNER_ONLY,
    # 監査ログは書いたテナントだけが読む。相手テナントへの写しは作らない
    "audit_logs" => OWNER_ONLY,
    # 送信記録は送ったテナントだけが読む。宛先は自社のユーザーで、相手テナントへ送る通知は無い
    "email_deliveries" => OWNER_ONLY
  }.freeze
end
