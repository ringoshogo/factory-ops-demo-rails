module Sales
  # 取消の審査の値。連結元の取消依頼 ID は相手側を指すので持たない。decision は :approved・:rejected の記号か、審査中なら空
  CancellationReviewValue = Data.define(:id, :owner_tenant_id, :sales_order_id, :requested_at, :decision, :decided_at)
end
