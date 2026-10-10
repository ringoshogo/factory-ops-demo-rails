require "rails_helper"
require_relative "../support/tenant_helpers"

# ジョブのログの文脈（docs/guides/config.md「ログ」、docs/adr/005 決定 3）。ApplicationJob#perform_now は、
# 引数を復元せずに付帯情報から文脈を設定する。文脈は Active Job の計装と例外の処理の外側で設定するので、
# 開始・終了・再試行・破棄のイベントと、引数の復元に失敗したときの再試行・破棄にも付く。
# ログとエラー通知の文脈は、呼び出し元の文脈を引き継がずにジョブの文脈に置き換わり、実行の後は前の文脈に丸ごと戻る
RSpec.describe ApplicationJob do
  include TenantHelpers

  let!(:tenant_id) { create_tenant("log-context") }
  let(:seen) { [] }
  let(:collector) do
    seen = self.seen
    Class.new { define_method(:emit) { |event| seen << [ event[:name], event[:context] ] } }.new
  end
  let(:reported) { [] }
  let(:error_collector) do
    reported = self.reported
    Class.new { define_method(:report) { |_error, context:, **| reported << context } }.new
  end

  # 本体の中の文脈は、ワーカーの経路でも同じ配列に集める。引数で渡すと、直列化で別の配列になる
  before do
    stub_const("LogContextSpecSeen", seen)
    stub_const("RetrySpecError", Class.new(StandardError))
    stub_const("LogContextSpecJob", Class.new(described_class) do
      retry_on RetrySpecError, wait: 0, attempts: 2

      def perform(outcome)
        # ジョブの中で足した項目も、実行の後に残らない
        Rails.error.set_context(added_in_job: "x")
        LogContextSpecSeen << [ "perform", Rails.event.context, LogContextSpecErrorContext.call ]
        raise ArgumentError, "失敗" if outcome == "fail"
        raise RetrySpecError if outcome == "retry"
        return unless outcome == "nest"

        LogContextSpecInnerJob.new.tap { _1.app_metadata = { "tenant_id" => "other-tenant", "correlation_id" => "corr-2" } }.perform_now
        LogContextSpecSeen << [ "after_nested", Rails.event.context, LogContextSpecErrorContext.call ]
      end
    end)
    stub_const("LogContextSpecInnerJob", Class.new(described_class) do
      def perform = LogContextSpecSeen << [ "inner", Rails.event.context, LogContextSpecErrorContext.call ]
    end)
    comparable = self.class.method(:comparable)
    stub_const("LogContextSpecErrorContext", -> { comparable.call(ActiveSupport::ExecutionContext.to_h) })
    Rails.event.subscribe(collector)
    Rails.error.subscribe(error_collector)
  end

  after do
    Rails.event.unsubscribe(collector)
    Rails.error.unsubscribe(error_collector)
  end

  # 要求の中でジョブを作る。付帯情報は、作った時点の相関 ID とテナントを持つ
  def build(job_class, *arguments)
    Rails.event.set_context(request_id: "req-1", correlation_id: "corr-1")
    Tenancy.with_tenant(tenant_id) { job_class.new(*arguments) }
  ensure
    Rails.event.clear_context
  end

  def job_context(job, job_class: "LogContextSpecJob")
    { job_id: job.job_id, job_class:, queue: "default", tenant_id:, correlation_id: "corr-1" }
  end

  # エラー通知の文脈の全体。項目の集合ごと比べ、ジョブは job_id で比べる
  def self.comparable(context)
    context.transform_values { _1.is_a?(ActiveJob::Base) ? _1.job_id : _1 }
  end

  # LogContextSpecJob の本体は、ジョブの文脈に added_in_job を足す
  def job_error_context(job) = { job: job.job_id, tenant_id:, correlation_id: "corr-1", added_in_job: "x" }

  OUTER_EVENT_CONTEXT = { request_id: "outer", user_id: "outer-user" }.freeze
  OUTER_ERROR_CONTEXT = { request_id: "outer", user_id: "outer-user", tenant_id: "outer-tenant", correlation_id: "outer-corr" }.freeze

  # 直接の perform_now は executor の外で動かす。ワーカーは、Solid Queue が executor で包んだ中で ActiveJob::Base.execute を呼ぶ
  PATHS = {
    "直接の perform_now" => ->(job, &block) { block.call { job.perform_now } },
    "ワーカーの経路" => ->(job, &block) { Rails.application.executor.wrap { block.call { ActiveJob::Base.execute(job.serialize) } } }
  }.freeze

  # 実行の前に要求の文脈を置き、実行の後の文脈を返す。例外は呼び出し元へ上げずに返す
  def run(path, job)
    PATHS.fetch(path).call(job) do |&perform|
      Rails.event.set_context(OUTER_EVENT_CONTEXT)
      Rails.error.set_context(**OUTER_ERROR_CONTEXT)
      error = begin
        perform.call
        nil
      rescue => e
        e
      end
      { error:, event_context: Rails.event.context, error_context: self.class.comparable(ActiveSupport::ExecutionContext.to_h) }
    end
  end

  def restored = { event_context: OUTER_EVENT_CONTEXT, error_context: OUTER_ERROR_CONTEXT }

  def contexts_of(name)
    seen.select { _1.first == name }.map(&:second)
  end

  PATHS.each_key do |path|
    describe path do
      it "成功では、開始・終了のイベントと本体の中で、付帯情報とテナントから文脈が設定され、実行の後は前の文脈に戻る" do
        job = build(LogContextSpecJob, "ok")

        after = run(path, job)

        expect(after).to eq(error: nil, **restored)
        expect(contexts_of("active_job.started")).to eq([ job_context(job) ])
        expect(contexts_of("active_job.completed")).to eq([ job_context(job) ])
        expect(seen.assoc("perform")).to eq([ "perform", job_context(job), job_error_context(job) ])
      end

      it "失敗では、終了のイベントに文脈が付き、エラー通知の文脈にテナント ID が入る" do
        job = build(LogContextSpecJob, "fail")

        after = run(path, job)

        expect(after).to include(error: be_a(ArgumentError), **restored)
        expect(contexts_of("active_job.started")).to eq([ job_context(job) ])
        expect(contexts_of("active_job.completed")).to eq([ job_context(job) ])
        expect(reported.map { self.class.comparable(_1) }).to eq([ job_error_context(job) ])
      end

      it "再試行では、再試行のイベントに文脈が付き、登録し直したジョブが同じ付帯情報を持つ" do
        job = build(LogContextSpecJob, "retry")

        expect(run(path, job)).to eq(error: nil, **restored)
        expect(contexts_of("active_job.started")).to eq([ job_context(job) ])
        expect(contexts_of("active_job.retry_scheduled")).to eq([ job_context(job) ])
        expect(contexts_of("active_job.completed")).to eq([ job_context(job) ])
        expect(SolidQueue::Job.where(active_job_id: job.job_id).map { _1.arguments["app_metadata"] })
          .to eq([ { "correlation_id" => "corr-1", "tenant_id" => tenant_id } ])
      end

      it "付帯情報の無いジョブは、付帯情報の文脈を設定せず、呼び出し元の文脈も引き継がない" do
        job = build(LogContextSpecJob, "ok").tap { _1.app_metadata = nil }

        expect(run(path, job)).to eq(error: nil, **restored)
        expect(seen.assoc("perform"))
          .to eq([ "perform", { job_id: job.job_id, job_class: "LogContextSpecJob", queue: "default" }, { job: job.job_id, added_in_job: "x" } ])
      end

      it "ジョブの中で別のジョブを動かすと、内側はその付帯情報の文脈になり、抜けた後は外側の文脈に戻る" do
        job = build(LogContextSpecJob, "nest")

        expect(run(path, job)).to eq(error: nil, **restored)
        inner = seen.assoc("inner")
        expect(inner.second).to include(job_class: "LogContextSpecInnerJob", tenant_id: "other-tenant", correlation_id: "corr-2")
        expect(inner.third).to eq(job: inner.second[:job_id], tenant_id: "other-tenant", correlation_id: "corr-2")
        expect(seen.assoc("after_nested")).to eq([ "after_nested", job_context(job), job_error_context(job) ])
      end
    end
  end

  describe "ワーカーの経路で引数の復元に失敗するジョブ" do
    let(:after_discard) { [] }

    # 消したレコードを指す GlobalID を引数に持つ。復元は perform_now の中の、再試行・破棄の処理の内側で行われる
    def build_undeserializable(handling)
      stub_const("LogContextSpecRecord", Class.new(ApplicationRecord) { self.table_name = "tenants" })
      after_discard = self.after_discard
      stub_const("LogContextSpecDeserializeJob", Class.new(described_class) do
        discard_on ActiveJob::DeserializationError if handling == :discard
        retry_on ActiveJob::DeserializationError, wait: 0, attempts: 2 if handling == :retry
        after_discard { after_discard << Rails.event.context }

        def perform(_record) = nil
      end)
      build(LogContextSpecDeserializeJob, LogContextSpecRecord.new(id: SecureRandom.uuid_v7))
    end

    def deserialize_job_context(job)
      job_context(job, job_class: "LogContextSpecDeserializeJob")
    end

    it "discard_on では、after_discard が呼ばれ、破棄のイベントが出る。どちらも文脈が付く" do
      job = build_undeserializable(:discard)

      expect(run("ワーカーの経路", job)).to eq(error: nil, **restored)
      expect(after_discard).to eq([ deserialize_job_context(job) ])
      expect(contexts_of("active_job.discarded")).to eq([ deserialize_job_context(job) ])
      expect(contexts_of("active_job.completed")).to eq([ deserialize_job_context(job) ])
    end

    it "retry_on では、再試行のイベントが出て、登録し直したジョブが同じ付帯情報を持つ" do
      job = build_undeserializable(:retry)

      expect(run("ワーカーの経路", job)).to eq(error: nil, **restored)
      expect(contexts_of("active_job.retry_scheduled")).to eq([ deserialize_job_context(job) ])
      expect(contexts_of("active_job.completed")).to eq([ deserialize_job_context(job) ])
      expect(SolidQueue::Job.where(active_job_id: job.job_id).map { _1.arguments["app_metadata"] })
        .to eq([ { "correlation_id" => "corr-1", "tenant_id" => tenant_id } ])
    end

    it "どちらも無ければ、例外が呼び出し元へ上がり、エラー通知と終了のイベントに文脈が付く" do
      job = build_undeserializable(:none)

      expect(run("ワーカーの経路", job)).to include(error: be_a(ActiveJob::DeserializationError), **restored)
      expect(after_discard).to eq([ deserialize_job_context(job) ])
      expect(contexts_of("active_job.completed")).to eq([ deserialize_job_context(job) ])
      expect(reported.map { self.class.comparable(_1) })
        .to eq([ { job: job.job_id, tenant_id:, correlation_id: "corr-1" } ])
    end
  end
end
