module Contracts
  # 取消依頼（購買 → 受注）。requested_at は依頼を登録した時刻の ISO 8601 の文字列。
  # 取消の理由は自由記述なので運ばない（docs/guides/config.md「ログ」）
  CancellationRequested = Event.define(:cancellation_request_id, :purchase_order_id, :buyer_tenant_id, :supplier_tenant_id,
    :requested_at)
end
