module Imports
  # 置いたまま取り込みを始めないファイルの中身を消す定期のジョブ（config/recurring.yml）。テナントの表は RLS の下にあるので、
  # テナントを 1 つずつ開いて公開 API を呼ぶ（docs/architecture/decisions.md 2 章）
  class PurgeAbandonedFilesJob < ApplicationJob
    def perform
      tenant_ids = ActiveRecord::Base.lease_connection.select_values("SELECT id FROM tenants ORDER BY id")
      tenant_ids.each { |tenant_id| Tenancy.with_tenant(tenant_id) { Files.purge_abandoned } }
    end
  end
end
