module Sales
  # 受注の値。連結元の発注 ID は相手側を指すので持たない。status は SalesOrderStatus が導出した記号。
  # cancellation_review_pending は審査中の取消の審査があるか（取消審査中）で、状況に重ねて示す
  # （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
  # total_amount は SalesOrderAmount が計算した税抜の合計金額（Integer）で、品番照合待ちの明細を含めば nil
  SalesOrderValue = Data.define(:id, :owner_tenant_id, :order_no, :customer_tenant_id, :order_date, :due_date, :status,
    :cancellation_review_pending, :total_amount)
end
