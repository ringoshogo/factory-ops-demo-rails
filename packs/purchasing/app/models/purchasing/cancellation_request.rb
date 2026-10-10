module Purchasing
  # 取消依頼。outcome は受注側から届いた回答（approved / rejected）で、空は回答待ち。回答待ちは発注ごとに 1 件で、部分一意索引が守る
  class CancellationRequest < TenantRecord
    belongs_to :purchase_order, inverse_of: :cancellation_requests

    scope :pending, -> { where(outcome: nil) }
  end
end
