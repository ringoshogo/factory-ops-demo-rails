require "digest"
require "json"
require "time"

module Platform
  # Rails.event の 1 件のイベントを 1 行の JSON にして書く購読者（docs/guides/config.md「ログ」）。
  # Rails の構造化イベントは要求の引数・ジョブの引数・例外のメッセージを載せ、filter_parameters は名前で値を隠すだけなので、
  # イベントの名前ごとに書く項目を決め、表に無い項目を落とす
  class JsonLogSubscriber
    class NonHashPayload < StandardError; end

    JOB = %i[job_class job_id queue].freeze
    # 表に無いイベントは payload と tags を書かない
    FIELDS = {
      "action_controller.request_started" => %i[controller action format],
      "action_controller.request_completed" =>
        %i[controller action status duration_ms gc_time_ms view_runtime db_runtime queries_count cached_queries_count],
      "action_controller.rescue_from_handled" => %i[exception_class],
      "active_job.enqueued" => [ *JOB, :adapter, :aborted, :exception_class ],
      "active_job.enqueued_at" => [ *JOB, :scheduled_at, :adapter, :aborted, :exception_class ],
      "active_job.started" => [ *JOB, :enqueued_at ],
      "active_job.completed" => [ *JOB, :adapter, :aborted, :duration, :exception_class ],
      "active_job.retry_scheduled" => %i[job_class job_id executions wait_seconds exception_class],
      "active_job.retry_stopped" => %i[job_class job_id executions exception_class],
      "active_job.discarded" => %i[job_class job_id exception_class],
      "graphql.operation_completed" => %i[operation_name result user_error_codes duration_ms],
      "contracts.event_handled" => %i[event_name receiver delivery_lag_ms]
    }.freeze

    def initialize(io)
      @io = io
    end

    def emit(event)
      name, payload = event.values_at(:name, :payload)
      # Rails.event はハッシュのペイロードにだけ filter_parameters を掛ける。イベントのオブジェクトは素通しになる
      raise NonHashPayload, "Rails.event のペイロードはハッシュで渡す: #{name}" unless payload.nil? || payload.is_a?(Hash)

      line = { name: }
      if (fields = FIELDS[name])
        line[:payload] = (payload || {}).slice(*fields).merge(graphql_request(name, payload))
        line[:tags] = event[:tags]
      end
      line[:context] = event[:context]
      line[:timestamp] = Time.at(Rational(event[:timestamp], 1_000_000_000)).utc.iso8601(6)
      @io.write("#{line.to_json}\n")
    end

    private

    # GraphQL の要求の params は、クエリの本文と変数の値を書かず、操作名・クエリの要約・変数のキーに置き換える
    def graphql_request(name, payload)
      return {} unless name == "action_controller.request_started" && payload[:controller] == "GraphqlController"

      params = payload[:params] || {}
      query, variables = params.values_at("query", "variables")
      { operation_name: params["operationName"], query_sha256: query.is_a?(String) ? Digest::SHA256.hexdigest(query) : nil,
        variable_keys: variables.is_a?(Hash) ? variables.keys : [] }
    end
  end
end
