module Sales
  # 取消の審査。source_cancellation_request_id は発注側テナントの取消依頼への ID 参照で、関連を張らない。
  # decision は担当者の決着（approved / rejected）で、空は審査中。審査中は受注ごとに 1 件で、部分一意索引が守る
  class CancellationReview < TenantRecord
    belongs_to :sales_order, inverse_of: :cancellation_reviews

    scope :pending, -> { where(decision: nil) }
  end
end
