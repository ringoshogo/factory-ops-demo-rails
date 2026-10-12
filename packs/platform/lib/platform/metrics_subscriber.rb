module Platform
  # Rails.event の構造化イベントからメトリクスを作る購読者（docs/guides/config.md「メトリクス」）。値の出どころはこの 1 つにし、
  # キューの滞留だけを収集の時点で数える（Platform::Metrics.collect_queue_depths）。
  # ラベルにテナント・ユーザー・伝票の ID を入れない。値の種類が増え続け、メトリクスの基盤にテナントの情報が流れるからである
  class MetricsSubscriber
    OUTCOMES = { "success" => "ok", "user_error" => "user_error", "error" => "error" }.freeze
    # import_duration_seconds の size の境目。これ以下を small、超えれば large にする
    SMALL_IMPORT_ROWS = 10_000

    # operations は config/graphql_operations.yml。操作の種類ごとに、ラベルに使ってよい操作名を持つ
    def initialize(operations:)
      @operations = { "query" => operations.fetch(:queries).to_set, "mutation" => operations.fetch(:mutations).to_set }
    end

    def emit(event)
      payload = event[:payload]
      case event[:name]
      when "graphql.operation_completed" then graphql_operation(payload)
      when "active_job.started" then job_started(payload, event[:timestamp])
      when "active_job.completed"
        Yabeda.job_duration_seconds.measure(payload.slice(:queue, :job_class), seconds(payload[:duration]))
      when "contracts.event_handled"
        Yabeda.event_delivery_lag_seconds.measure({ event: payload[:event_name] }, seconds(payload[:delivery_lag_ms]))
      when "notifications.provider_responded" then Yabeda.external_requests_total.increment(payload.slice(:provider, :status))
      when "notification.accepted"
        Yabeda.notification_acceptance_seconds.measure(payload.slice(:kind), seconds(payload[:acceptance_ms]))
      when "notification.delivery_failed" then Yabeda.notification_failures_total.increment(payload.slice(:kind, :reason))
      when "notification.best_effort_dropped" then Yabeda.notification_dropped_total.increment(payload.slice(:kind, :reason))
      when "imports.chunk_applied" then import_rows(payload)
      when "imports.finished"
        # 行を数える前に失敗した取り込み（見出しの不一致・行数の上限超え・壊れた CSV）は total_rows が無い。反映した行が無いので small にする
        size = payload[:total_rows].to_i <= SMALL_IMPORT_ROWS ? "small" : "large"
        Yabeda.import_duration_seconds.measure({ kind: payload[:kind], size: }, seconds(payload[:duration_ms]))
      end
    end

    private

    def seconds(milliseconds) = milliseconds / 1000.0

    # 操作名は利用者が送る値なので、登録した名前でも、種類が違えば other にする
    def graphql_operation(payload)
      type = payload[:operation_type]
      name = payload[:operation_name]
      operation = @operations.fetch(type, Set.new).include?(name) ? name : "other"
      Yabeda.graphql_operation_duration_seconds.measure(
        { operation:, operation_type: type, outcome: OUTCOMES.fetch(payload[:result]) }, seconds(payload[:duration_ms]))

      # FORBIDDEN の 1 件ごとに出どころが 1 つ積まれている（ForbiddenError）。足りなければ next が例外を上げる
      reasons = payload[:forbidden_reasons].each
      payload[:error_codes].each do |code|
        Yabeda.graphql_top_level_errors_total.increment({ operation:, code:, reason: code == "FORBIDDEN" ? reasons.next : "none" })
      end
    end

    # 受け取った時刻はイベントの時刻（ナノ秒）。enqueued_at は ISO 8601 の文字列（activejob 8.1.4 の
    # lib/active_job/structured_event_subscriber.rb の perform_start）
    def job_started(payload, timestamp)
      enqueued_at = payload[:enqueued_at] or return

      latency = Rational(timestamp, 1_000_000_000) - Time.iso8601(enqueued_at).to_r
      Yabeda.job_queue_latency_seconds.measure(payload.slice(:queue), latency.to_f)
    end

    def import_rows(payload)
      Yabeda.import_rows_total.increment({ kind: payload[:kind], result: "applied" }, by: payload[:applied_rows])
      Yabeda.import_rows_total.increment({ kind: payload[:kind], result: "failed" }, by: payload[:failed_rows])
    end
  end
end
