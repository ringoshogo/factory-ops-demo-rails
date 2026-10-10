module Fulfillment
  # 出荷停止。sales_order_id は受注の行の、source_cancellation_review_id は取消の審査の ID 参照で、関連を張らない。
  # 出荷依頼とは別の表に置くのは、全量の引当より前の、出荷依頼がまだ無い受注も止めるためである
  # （docs/architecture/data-model.md「出荷（`fulfillment`）」）
  class ShippingHold < TenantRecord
    scope :active, -> { where(released_at: nil) }
  end
end
