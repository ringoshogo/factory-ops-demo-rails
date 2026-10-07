class ApplicationJob < ActiveJob::Base
  # 投入の時機を基底クラスに明示する。Rails の更新で既定値が変わっても黙って切り替わらない（docs/adr/005 決定 2）
  self.enqueue_after_transaction_commit = true

  # 投入した時のテナントを覚え、実行時に Tenancy.with_tenant で復元する（decisions.md 2 章）。
  # コミットの後に投入するジョブは、投入の時点で Tenancy.with_tenant を抜けているので、作った時点で覚える
  def initialize(...)
    super
    @tenant_id = Current.tenant_id
  end

  def serialize
    super.merge("tenant_id" => @tenant_id)
  end

  def deserialize(job_data)
    super
    @tenant_id = job_data["tenant_id"]
  end

  around_perform do |job, block|
    tenant_id = job.perform_tenant_id
    tenant_id ? Tenancy.with_tenant(tenant_id, &block) : block.call
  end

  # 実行時に設定するテナント。空ならテナントを設定せずに実行する
  def perform_tenant_id
    @tenant_id
  end
end
