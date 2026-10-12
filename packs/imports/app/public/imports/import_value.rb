module Imports
  # 取り込みの値。status は :failed・:partially_failed・:succeeded・:applying・:staging・:queued のどれか
  ImportValue = Data.define(:id, :owner_tenant_id, :kind, :status, :total_rows, :applied_rows, :failed_rows, :started_at,
    :finished_at)
end
