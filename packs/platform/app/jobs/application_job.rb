class ApplicationJob < ActiveJob::Base
  # 投入の時機を基底クラスに明示する。Rails の更新で既定値が変わっても黙って切り替わらない（docs/adr/005 決定 2）
  self.enqueue_after_transaction_commit = true

  # ジョブの引数は伝票の ID や宛先を運び、イベントのペイロードを含むので、ログに書かない（docs/guides/config.md「ログ」）
  self.log_arguments = false

  # ログとエラー通知の文脈に使う付帯情報。引数とは別に、直列化の最上位の項目に持つ（docs/adr/005 決定 3）。
  # ジョブが開くテナントには使わない。それは引数・ペイロードと、下の @tenant_id で決める
  attr_accessor :app_metadata

  # 投入した時のテナントを覚え、実行時に Tenancy.with_tenant で復元する（decisions.md 2 章）。
  # コミットの後に投入するジョブは、投入の時点で Tenancy.with_tenant を抜けているので、作った時点で覚える。
  # 付帯情報には、作った時点の相関 ID とテナントを入れる。イベントのジョブは Contracts.publish が置き換える
  def initialize(...)
    super
    @tenant_id = Current.tenant_id
    @app_metadata = { "correlation_id" => Rails.event.context[:correlation_id], "tenant_id" => Current.tenant_id }.compact
  end

  def serialize
    super.merge("tenant_id" => @tenant_id, "app_metadata" => app_metadata)
  end

  # Rails は引数を直列化したまま持ち、perform_now の中まで復元しないので、付帯情報は引数を復元せずに読める
  def deserialize(job_data)
    super
    @tenant_id = job_data["tenant_id"]
    @app_metadata = job_data["app_metadata"]
  end

  # 文脈を、Active Job の計装と例外の処理の外側で設定する。開始・終了・再試行・破棄のイベントは super の中で出る。
  # ここで引数を復元しない。復元は super の中の再試行・破棄の処理の内側で行われ、先に復元すると、
  # 復元の失敗が retry_on・discard_on・after_discard を通らない。
  # ログとエラー通知の文脈は、呼び出し元の文脈を引き継がずにジョブの文脈に置き換え、例外の経路も含めて実行の前の文脈に戻す。
  # executor の外（テストや直接の perform_now）と入れ子のジョブでは、戻さないと文脈が持ち越される
  def perform_now
    previous_event_context = Rails.event.context
    previous_error_context = ActiveSupport::ExecutionContext.to_h
    Rails.event.clear_context
    Rails.event.set_context(log_context)
    replace_error_context(job: self, **log_context.slice(:tenant_id, :correlation_id))
    super
  rescue Exception => error
    # ワーカーの実行器は、文脈を戻した後に例外を通知するので、ジョブの文脈の中で通知する。
    # 同じ例外の 2 回目の通知は、エラー通知が捨てる
    Rails.error.report(error, handled: false, source: "application.active_job")
    raise
  ensure
    Rails.event.clear_context
    Rails.event.set_context(previous_event_context)
    replace_error_context(previous_error_context)
  end

  around_perform do |job, block|
    tenant_id = job.perform_tenant_id
    tenant_id ? Tenancy.with_tenant(tenant_id, &block) : block.call
  end

  # 実行時に設定するテナント。空ならテナントを設定せずに実行する
  def perform_tenant_id
    @tenant_id
  end

  private

  # エラー通知の文脈を、項目の集合ごと置き換える。Rails.error.set_context は渡した項目だけを書き換え、
  # ActiveSupport::ExecutionContext.clear は CurrentAttributes の値と入れ子のスタックも捨てるので、どちらも使わない。
  # 文脈の置き場（record.store）は Rails 8.1.4 の内部なので、spec/jobs/log_context_spec.rb が項目の集合で確かめる。
  # 置き換えた後に引数なしの set を呼び、変更の通知（ActiveRecord::QueryLogs のキャッシュの消去）を出す
  def replace_error_context(context)
    ActiveSupport::ExecutionContext.send(:record).store.replace(context)
    ActiveSupport::ExecutionContext.set
  end

  # 付帯情報の無いジョブは、ジョブ自身の項目だけを設定する。イベントのジョブは、届いたイベントの ID を因果 ID にする
  def log_context
    metadata = app_metadata || {}
    { job_id:, job_class: self.class.name, queue: queue_name, tenant_id: metadata["tenant_id"],
      correlation_id: metadata["correlation_id"], causation_id: metadata["event_id"],
      event_id: metadata["event_id"], event_name: metadata["event_name"] }.compact
  end
end
